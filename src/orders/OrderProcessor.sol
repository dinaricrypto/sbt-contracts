// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {
    UUPSUpgradeable,
    Initializable
} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {
    AccessControlDefaultAdminRulesUpgradeable,
    AccessControlUpgradeable,
    IAccessControl
} from "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {EIP712Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/cryptography/EIP712Upgradeable.sol";
import {MulticallUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/MulticallUpgradeable.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {mulDiv, mulDiv18} from "prb-math/Common.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {SelfPermit} from "../common/SelfPermit.sol";
import {IOrderProcessor} from "./IOrderProcessor.sol";
import {ITransferRestrictor} from "../ITransferRestrictor.sol";
import {DShare, IDShare} from "../DShare.sol";
import {ITokenLockCheck} from "../ITokenLockCheck.sol";
import {FeeLib} from "../common/FeeLib.sol";

/// @notice Core contract managing orders for dShare tokens
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/orders/OrderProcessor.sol)
// TODO: take network fee from proceeds for sells
// FIXME: individual fees can be set when there is no default
contract OrderProcessor is
    Initializable,
    UUPSUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable,
    EIP712Upgradeable,
    MulticallUpgradeable,
    SelfPermit,
    IOrderProcessor
{
    using SafeERC20 for IERC20;

    /// ------------------ Types ------------------ ///

    // Order state cleared after order is fulfilled or cancelled.
    struct OrderState {
        // Hash of order data used to validate order details stored offchain
        bytes32 orderHash;
        // Flat fee at time of order request
        uint256 flatFee;
        // Percentage fee rate at time of order request
        uint24 percentageFeeRate;
        // Account that requested the order
        address requester;
        // Amount of order token remaining to be used
        uint256 unfilledAmount;
        // Total amount of received token due to fills
        uint256 received;
        // Total fees paid to treasury
        uint256 feesPaid;
        // Current amount of payment token taken out of escrow
        uint256 escrowTaken;
    }

    struct FeeRates {
        uint64 perOrderFeeBuy;
        uint24 percentageFeeRateBuy;
        uint64 perOrderFeeSell;
        uint24 percentageFeeRateSell;
    }

    struct FeeRatesStorage {
        bool set;
        uint64 perOrderFeeBuy;
        uint24 percentageFeeRateBuy;
        uint64 perOrderFeeSell;
        uint24 percentageFeeRateSell;
    }

    /// @dev Signature deadline expired
    error ExpiredSignature();
    error InvalidAccountNonce(address account, uint256 nonce);
    /// @dev Zero address
    error ZeroAddress();
    /// @dev Orders are paused
    error Paused();
    /// @dev Zero value
    error ZeroValue();
    /// @dev Order does not exist
    error OrderNotFound();
    /// @dev Invalid order data
    error InvalidOrderData();
    /// @dev Escrow unlock feature not supported for sells
    error EscrowUnlockNotSupported();
    /// @dev Amount too large
    error AmountTooLarge();
    error UnsupportedToken(address token);
    /// @dev blacklist address
    error Blacklist();
    /// @dev Thrown when assetTokenQuantity's precision doesn't match the expected precision in orderDecimals.
    error InvalidPrecision();
    error LimitPriceNotSet();
    error OrderFillBelowLimitPrice();
    error OrderFillAboveLimitPrice();
    error EscrowLocked();
    error UnreturnedEscrow();

    event EscrowTaken(uint256 indexed id, address indexed recipient, uint256 amount);
    event EscrowReturned(uint256 indexed id, address indexed recipient, uint256 amount);
    /// @dev Emitted when `treasury` is set
    event TreasurySet(address indexed treasury);
    /// @dev Emitted when orders are paused/unpaused
    event OrdersPaused(bool paused);
    /// @dev Emitted when token lock check contract is set
    event TokenLockCheckSet(ITokenLockCheck indexed tokenLockCheck);
    /// @dev Emitted when fees are set
    event FeesSet(address indexed account, address indexed paymentToken, FeeRates feeRates);
    /// @dev Emitted when OrderDecimal is set
    event MaxOrderDecimalsSet(address indexed assetToken, int8 decimals);
    event EthUsdOracleSet(address indexed ethUsdOracle);
    event PaymentTokenOracleSet(address indexed paymentToken, address indexed oracle);

    /// ------------------ Constants ------------------ ///

    /// @notice Operator role for filling and cancelling orders
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @notice Asset token role for whitelisting asset tokens
    /// @dev Tokens with decimals > 18 are not supported by current implementation
    bytes32 public constant ASSETTOKEN_ROLE = keccak256("ASSETTOKEN_ROLE");

    bytes32 private constant ORDER_TYPEHASH = keccak256(
        "Order(address recipient,address assetToken,address paymentToken,bool sell,uint8 orderType,uint256 assetTokenQuantity,uint256 paymentTokenQuantity,uint256 price,uint8 tif,bool escrowUnlocked)"
    );

    bytes32 private constant ORDER_REQUEST_TYPEHASH =
        keccak256("OrderRequest(bytes32 orderHash,uint256 deadline,uint256 nonce)");

    /// ------------------ State ------------------ ///

    struct OrderProcessorStorage {
        // Address to receive fees
        address _treasury;
        // Transfer restrictor checker
        ITokenLockCheck _tokenLockCheck;
        // Are orders paused?
        bool _ordersPaused;
        // Total number of active orders. Onchain enumeration not supported.
        uint256 _numOpenOrders;
        // Next order id
        uint256 _nextOrderId;
        // Active order state
        mapping(uint256 => OrderState) _orders;
        // Status of order
        mapping(uint256 => OrderStatus) _status;
        // Escrowed balance of asset token per requester
        mapping(address => mapping(address => uint256)) _escrowedBalanceOf;
        // Max order decimals for asset token, defaults to 0 decimals
        mapping(address => int8) _maxOrderDecimals;
        // Fee schedule for requester, per paymentToken
        // Uses address(0) to store default fee schedule
        mapping(address => mapping(address => FeeRatesStorage)) _accountFees;
        // ETH USD price oracle
        address _ethUsdOracle;
        // Payment token USD price oracles
        mapping(address => address) _paymentTokenOracle;
        // User order consumed nonces
        mapping(address => mapping(uint256 => bool)) _usedNonces;
    }

    // keccak256(abi.encode(uint256(keccak256("dinaricrypto.storage.OrderProcessor")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OrderProcessorStorageLocation =
        0x8036d9ca2814a3bcd78d3e8aba96b71e7697006bd322a98e7f5f0f41b09a8b00;

    function _getOrderProcessorStorage() private pure returns (OrderProcessorStorage storage $) {
        assembly {
            $.slot := OrderProcessorStorageLocation
        }
    }

    /// ------------------ Initialization ------------------ ///

    /// @notice Initialize contract
    /// @param _owner Owner of contract
    /// @param _treasury Address to receive fees
    /// @param _tokenLockCheck Token lock check contract
    /// @dev Treasury cannot be zero address
    function initialize(address _owner, address _treasury, ITokenLockCheck _tokenLockCheck, address _ethUsdOracle)
        public
        virtual
        initializer
    {
        __AccessControlDefaultAdminRules_init(0, _owner);
        __EIP712_init("OrderProcessor", "1");
        __Multicall_init();

        // Don't send fees to zero address
        if (_treasury == address(0)) revert ZeroAddress();
        if (_ethUsdOracle == address(0)) revert ZeroAddress();

        // Initialize
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._treasury = _treasury;
        $._tokenLockCheck = _tokenLockCheck;
        $._ethUsdOracle = _ethUsdOracle;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// ------------------ Getters ------------------ ///

    /// @notice Address to receive fees
    function treasury() external view returns (address) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._treasury;
    }

    /// @notice Transfer restrictor checker
    function tokenLockCheck() external view returns (ITokenLockCheck) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._tokenLockCheck;
    }

    /// @notice Are orders paused?
    function ordersPaused() external view returns (bool) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._ordersPaused;
    }

    /// @inheritdoc IOrderProcessor
    function numOpenOrders() external view override returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._numOpenOrders;
    }

    /// @inheritdoc IOrderProcessor
    function nextOrderId() external view override returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._nextOrderId;
    }

    /// @inheritdoc IOrderProcessor
    function escrowedBalanceOf(address token, address requester) external view override returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._escrowedBalanceOf[token][requester];
    }

    /// @inheritdoc IOrderProcessor
    function maxOrderDecimals(address token) external view override returns (int8) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._maxOrderDecimals[token];
    }

    /// @inheritdoc IOrderProcessor
    function getOrderStatus(uint256 id) external view returns (OrderStatus) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._status[id];
    }

    /// @inheritdoc IOrderProcessor
    function getUnfilledAmount(uint256 id) external view returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._orders[id].unfilledAmount;
    }

    /// @inheritdoc IOrderProcessor
    function getTotalReceived(uint256 id) external view returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._orders[id].received;
    }

    /// @notice Get current amount of payment token taken out of escrow
    /// @param id order id
    function getEscrowTaken(uint256 id) external view returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._orders[id].escrowTaken;
    }

    function ethUsdOracle() external view returns (address) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._ethUsdOracle;
    }

    function paymentTokenOracle(address paymentToken) external view returns (address) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._paymentTokenOracle[paymentToken];
    }

    function nonceUsed(address account, uint256 nonce) external view returns (bool) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._usedNonces[account][nonce];
    }

    function getAccountFees(address requester, address paymentToken) public view returns (FeeRates memory) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        FeeRatesStorage storage feeRatesPointer = $._accountFees[requester][paymentToken];
        // If user, paymentToken does not have a custom fee schedule, use default
        FeeRatesStorage memory feeRates;
        if (feeRatesPointer.set) {
            feeRates = feeRatesPointer;
        } else {
            feeRates = $._accountFees[address(0)][paymentToken];
        }
        return FeeRates({
            perOrderFeeBuy: feeRates.perOrderFeeBuy,
            percentageFeeRateBuy: feeRates.percentageFeeRateBuy,
            perOrderFeeSell: feeRates.perOrderFeeSell,
            percentageFeeRateSell: feeRates.percentageFeeRateSell
        });
    }

    /// @inheritdoc IOrderProcessor
    function getFeeRatesForOrder(address requester, bool sell, address paymentToken)
        public
        view
        returns (uint256, uint24)
    {
        FeeRates memory feeRates = getAccountFees(requester, paymentToken);
        if (sell) {
            return (FeeLib.flatFeeForOrder(paymentToken, feeRates.perOrderFeeSell), feeRates.percentageFeeRateSell);
        } else {
            return (FeeLib.flatFeeForOrder(paymentToken, feeRates.perOrderFeeBuy), feeRates.percentageFeeRateBuy);
        }
    }

    // slither-disable-next-line naming-convention
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// ------------------ Administration ------------------ ///

    /// @dev Check if orders are paused
    modifier whenOrdersNotPaused() {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        if ($._ordersPaused) revert Paused();
        _;
    }

    /// @notice Set treasury address
    /// @param account Address to receive fees
    /// @dev Only callable by admin
    /// Treasury cannot be zero address
    function setTreasury(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Don't send fees to zero address
        if (account == address(0)) revert ZeroAddress();

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._treasury = account;
        emit TreasurySet(account);
    }

    /// @notice Pause/unpause orders
    /// @param pause Pause orders if true, unpause if false
    /// @dev Only callable by admin
    function setOrdersPaused(bool pause) external onlyRole(DEFAULT_ADMIN_ROLE) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._ordersPaused = pause;
        emit OrdersPaused(pause);
    }

    /// @notice Set token lock check contract
    /// @param _tokenLockCheck Token lock check contract
    /// @dev Only callable by admin
    function setTokenLockCheck(ITokenLockCheck _tokenLockCheck) external onlyRole(DEFAULT_ADMIN_ROLE) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._tokenLockCheck = _tokenLockCheck;
        emit TokenLockCheckSet(_tokenLockCheck);
    }

    /// @notice Set unique fee rates for requester
    /// @param requester Requester address
    /// @param paymentToken Payment token
    /// @param feeRates Fee rates
    /// @dev Only callable by admin, set zero address to set default
    function setFees(address requester, address paymentToken, FeeRates memory feeRates)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        FeeLib.checkPercentageFeeRate(feeRates.percentageFeeRateBuy);
        FeeLib.checkPercentageFeeRate(feeRates.percentageFeeRateSell);

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._accountFees[requester][paymentToken] = FeeRatesStorage({
            set: true,
            perOrderFeeBuy: feeRates.perOrderFeeBuy,
            percentageFeeRateBuy: feeRates.percentageFeeRateBuy,
            perOrderFeeSell: feeRates.perOrderFeeSell,
            percentageFeeRateSell: feeRates.percentageFeeRateSell
        });
        emit FeesSet(requester, paymentToken, feeRates);
    }

    /// @notice Reset fee rates for requester to default
    /// @param requester Requester address
    /// @param paymentToken Payment token
    /// @dev Only callable by admin
    function resetFees(address requester, address paymentToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (requester == address(0)) revert ZeroAddress();

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        delete $._accountFees[requester][paymentToken];
        FeeRatesStorage memory defaultFeeRates = $._accountFees[address(0)][paymentToken];
        emit FeesSet(
            requester,
            paymentToken,
            FeeRates({
                perOrderFeeBuy: defaultFeeRates.perOrderFeeBuy,
                percentageFeeRateBuy: defaultFeeRates.percentageFeeRateBuy,
                perOrderFeeSell: defaultFeeRates.perOrderFeeSell,
                percentageFeeRateSell: defaultFeeRates.percentageFeeRateSell
            })
        );
    }

    /// @notice Set max order decimals for asset token
    /// @param token Asset token
    /// @param decimals Max order decimals
    /// @dev Only callable by admin
    function setMaxOrderDecimals(address token, int8 decimals) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint8 tokenDecimals = IERC20Metadata(token).decimals();
        if (decimals > int8(tokenDecimals)) revert InvalidPrecision();
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._maxOrderDecimals[token] = decimals;
        emit MaxOrderDecimalsSet(token, decimals);
    }

    function setEthUsdOracle(address _ethUsdOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._ethUsdOracle = _ethUsdOracle;
        emit EthUsdOracleSet(_ethUsdOracle);
    }

    function setPaymentTokenOracle(address paymentToken, address oracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._paymentTokenOracle[paymentToken] = oracle;
        emit PaymentTokenOracleSet(paymentToken, oracle);
    }

    /// ------------------ Order Lifecycle ------------------ ///

    /// @inheritdoc IOrderProcessor
    function pullPaymentForSignedOrder(Order calldata order, Signature calldata signature)
        external
        whenOrdersNotPaused
        onlyRole(OPERATOR_ROLE)
        returns (uint256 id)
    {
        // Start gas measurement
        uint256 gasStart = gasleft();

        // Check if payment token oracle is set
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        address _oracle = $._paymentTokenOracle[order.paymentToken];
        if (_oracle == address(0)) revert UnsupportedToken(order.paymentToken);

        // Recover requester and validate signature
        if (signature.deadline < block.timestamp) revert ExpiredSignature();

        // Recover order requester
        bytes32 typedDataHash = _hashTypedDataV4(hashOrderRequest(order, signature.deadline, signature.nonce));
        address requester = ECDSA.recover(typedDataHash, signature.signature);

        // Consume nonce
        if ($._usedNonces[requester][signature.nonce]) revert InvalidAccountNonce(requester, signature.nonce);
        $._usedNonces[requester][signature.nonce] = true;

        // Create order
        id = _initializeOrder(order, requester);

        // Pull payment for order creation
        uint256 tokenPriceInWei = getTokenPriceInWei(_oracle);

        // Charge user for gas fees
        _chargeSponsoredTransaction(requester, order.paymentToken, tokenPriceInWei, gasStart);
    }

    /// @dev Validate order, initialize order state, and pull tokens
    // slither-disable-next-line cyclomatic-complexity
    function _initializeOrder(Order calldata order, address requester) private returns (uint256 id) {
        // ------------------ Checks ------------------ //

        // cheap checks first
        if (order.recipient == address(0)) revert ZeroAddress();
        uint256 orderAmount = (order.sell) ? order.assetTokenQuantity : order.paymentTokenQuantity;
        // No zero orders
        if (orderAmount == 0) revert ZeroValue();
        // Ensure that price is set for limit orders
        if (order.orderType == OrderType.LIMIT && order.price == 0) revert LimitPriceNotSet();
        // Escrow unlock not supported for sells
        if (order.escrowUnlocked && order.sell) revert EscrowUnlockNotSupported();

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();

        // Check for whitelisted tokens
        if (!hasRole(ASSETTOKEN_ROLE, order.assetToken)) revert UnsupportedToken(order.assetToken);
        if (!$._accountFees[address(0)][order.paymentToken].set) revert UnsupportedToken(order.paymentToken);

        // Precision checked for assetTokenQuantity, market buys excluded
        if (order.sell || order.orderType == OrderType.LIMIT) {
            // Check for max order decimals (assetTokenQuantity)
            uint8 assetTokenDecimals = IERC20Metadata(order.assetToken).decimals();
            uint256 assetPrecision = 10 ** uint8(int8(assetTokenDecimals) - $._maxOrderDecimals[order.assetToken]);
            if (order.assetTokenQuantity % assetPrecision != 0) revert InvalidPrecision();
        }

        // black list checker
        // TODO: try moving stored call here to reduce cost of external call
        ITokenLockCheck _tokenLockCheck = $._tokenLockCheck;
        if (
            _tokenLockCheck.isTransferLocked(order.assetToken, order.recipient)
                || _tokenLockCheck.isTransferLocked(order.assetToken, requester)
                || _tokenLockCheck.isTransferLocked(order.paymentToken, order.recipient)
                || _tokenLockCheck.isTransferLocked(order.paymentToken, requester)
        ) revert Blacklist();

        // ------------------ Effects ------------------ //

        // Update next order id
        id = $._nextOrderId++;

        // Calculate fees
        (uint256 flatFee, uint24 percentageFeeRate) = getFeeRatesForOrder(requester, order.sell, order.paymentToken);
        // Initialize order state
        $._orders[id] = OrderState({
            orderHash: hashOrder(order),
            requester: requester,
            flatFee: flatFee,
            percentageFeeRate: percentageFeeRate,
            unfilledAmount: orderAmount,
            received: 0,
            feesPaid: 0,
            escrowTaken: 0
        });
        $._status[id] = OrderStatus.ACTIVE;
        $._numOpenOrders++;

        emit OrderCreated(id, requester);

        // ------------------ Interactions ------------------ //

        if (order.sell) {
            // update escrowed balance
            $._escrowedBalanceOf[order.assetToken][requester] += order.assetTokenQuantity;

            // Transfer asset to contract
            IERC20(order.assetToken).safeTransferFrom(requester, address(this), order.assetTokenQuantity);
        } else {
            uint256 totalFees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, order.paymentTokenQuantity);
            uint256 quantityIn = order.paymentTokenQuantity + totalFees;
            // update escrowed balance
            $._escrowedBalanceOf[order.paymentToken][requester] += quantityIn;

            // Escrow payment for purchase
            IERC20(order.paymentToken).safeTransferFrom(requester, address(this), quantityIn);
        }
    }

    /**
     * @notice Get the current oracle price for a payment token
     */
    function getTokenPriceInWei(address _paymentTokenOracle) public view returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        address _ethUsdOracle = $._ethUsdOracle;

        // slither-disable-next-line unused-return
        (, int256 paymentPrice,,,) = AggregatorV3Interface(_paymentTokenOracle).latestRoundData();
        // slither-disable-next-line unused-return
        (, int256 ethUSDPrice,,,) = AggregatorV3Interface(_ethUsdOracle).latestRoundData();
        // adjust values to align decimals
        uint8 paymentPriceDecimals = AggregatorV3Interface(_paymentTokenOracle).decimals();
        uint8 ethUSDPriceDecimals = AggregatorV3Interface(_ethUsdOracle).decimals();
        if (paymentPriceDecimals > ethUSDPriceDecimals) {
            ethUSDPrice = ethUSDPrice * int256(10 ** (paymentPriceDecimals - ethUSDPriceDecimals));
        } else if (paymentPriceDecimals < ethUSDPriceDecimals) {
            paymentPrice = paymentPrice * int256(10 ** (ethUSDPriceDecimals - paymentPriceDecimals));
        }
        // compute payment price in wei
        uint256 paymentPriceInWei = mulDiv(uint256(paymentPrice), 1 ether, uint256(ethUSDPrice));
        return uint256(paymentPriceInWei);
    }

    /// @notice Take payment for gas fees
    function _chargeSponsoredTransaction(
        address user,
        address paymentToken,
        uint256 paymentTokenPrice,
        uint256 gasStart
    ) private {
        uint256 gasUsed = gasStart - gasleft();
        uint256 gasCostInWei = gasUsed * tx.gasprice;

        // Apply payment token price to calculate payment amount
        // Assumes payment token price includes token decimals
        uint256 paymentAmount = 0;
        try IERC20Metadata(paymentToken).decimals() returns (uint8 tokenDecimals) {
            paymentAmount = gasCostInWei * 10 ** tokenDecimals / paymentTokenPrice;
        } catch {
            paymentAmount = gasCostInWei / paymentTokenPrice;
        }

        // Transfer the payment for gas fees
        // slither-disable-next-line arbitrary-send-erc20
        IERC20(paymentToken).safeTransferFrom(user, msg.sender, paymentAmount);
    }

    /// @inheritdoc IOrderProcessor
    function requestOrder(Order calldata order) external whenOrdersNotPaused returns (uint256 id) {
        id = _initializeOrder(order, msg.sender);

        // Send order to bridge
        emit OrderRequested(id, msg.sender, order);
    }

    function hashOrderRequest(Order calldata order, uint256 deadline, uint256 nonce) public pure returns (bytes32) {
        return keccak256(abi.encode(ORDER_REQUEST_TYPEHASH, hashOrder(order), deadline, nonce));
    }

    /// @notice Hash order data for validation
    function hashOrder(Order calldata order) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                order.recipient,
                order.assetToken,
                order.paymentToken,
                order.sell,
                order.orderType,
                order.assetTokenQuantity,
                order.paymentTokenQuantity,
                order.price,
                order.tif,
                order.escrowUnlocked
            )
        );
    }

    /// @inheritdoc IOrderProcessor
    // slither-disable-next-line cyclomatic-complexity
    function fillOrder(uint256 id, Order calldata order, uint256 fillAmount, uint256 receivedAmount)
        external
        onlyRole(OPERATOR_ROLE)
    {
        // ------------------ Checks ------------------ //

        // No nonsense
        if (fillAmount == 0) revert ZeroValue();

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        OrderState memory orderState = $._orders[id];

        // Order must exist
        if (orderState.requester == address(0)) revert OrderNotFound();
        // Verify order data
        if (orderState.orderHash != hashOrder(order)) revert InvalidOrderData();
        // Fill cannot exceed remaining order
        if (fillAmount > orderState.unfilledAmount) revert AmountTooLarge();

        // Calculate earned fees and handle any unique checks
        uint256 paymentEarned = 0;
        uint256 feesEarned = 0;
        if (order.sell) {
            // For limit sell orders, ensure that the received amount is greater or equal to limit price * fill amount, order price has ether decimals
            if (order.orderType == OrderType.LIMIT && receivedAmount < mulDiv18(fillAmount, order.price)) {
                revert OrderFillAboveLimitPrice();
            }

            // Fees - earn up to the flat fee, then earn percentage fee on the remainder
            // TODO: make sure that all fees are taken at total fill to prevent dust accumulating here
            // Determine the subtotal used to calculate the percentage fee
            uint256 subtotal = 0;
            // If the flat fee hasn't been fully covered yet, ...
            if (orderState.feesPaid < orderState.flatFee) {
                // How much of the flat fee is left to cover?
                uint256 flatFeeRemaining = orderState.flatFee - orderState.feesPaid;
                // If the amount subject to fees is greater than the remaining flat fee, ...
                if (receivedAmount > flatFeeRemaining) {
                    // Earn the remaining flat fee
                    feesEarned = flatFeeRemaining;
                    // Calculate the subtotal by subtracting the remaining flat fee from the amount subject to fees
                    subtotal = receivedAmount - flatFeeRemaining;
                } else {
                    // Otherwise, earn the amount subject to fees
                    feesEarned = receivedAmount;
                }
            } else {
                // If the flat fee has been fully covered, the subtotal is the entire fill amount
                subtotal = receivedAmount;
            }

            // Calculate the percentage fee on the subtotal
            if (subtotal > 0 && orderState.percentageFeeRate > 0) {
                feesEarned += mulDiv18(subtotal, orderState.percentageFeeRate);
            }

            paymentEarned = receivedAmount - feesEarned;
        } else {
            // For limit buy orders, ensure that the received amount is greater or equal to fill amount / limit price, order price has ether decimals
            if (order.orderType == OrderType.LIMIT && receivedAmount < mulDiv(fillAmount, 1 ether, order.price)) {
                revert OrderFillBelowLimitPrice();
            }

            // Fees - earn the flat fee if first fill, then earn percentage fee on the fill
            feesEarned = 0;
            if (orderState.feesPaid == 0) {
                feesEarned = orderState.flatFee;
            }
            uint256 estimatedTotalFees =
                FeeLib.estimateTotalFees(orderState.flatFee, orderState.percentageFeeRate, order.paymentTokenQuantity);
            uint256 totalPercentageFees = estimatedTotalFees - orderState.flatFee;
            feesEarned += mulDiv(totalPercentageFees, fillAmount, order.paymentTokenQuantity);

            // Payment amount to take for fill reduced by amount previously taken from escrow
            if (order.escrowUnlocked) {
                if (fillAmount > orderState.escrowTaken) {
                    paymentEarned = fillAmount - orderState.escrowTaken;
                }
            } else {
                paymentEarned = fillAmount;
            }
        }

        // ------------------ Effects ------------------ //

        // Notify order filled
        emit OrderFill(
            id, orderState.requester, order.paymentToken, order.assetToken, fillAmount, receivedAmount, feesEarned
        );

        // Update order state
        uint256 newUnfilledAmount = orderState.unfilledAmount - fillAmount;
        // If order is completely filled then clear order state
        if (newUnfilledAmount == 0) {
            $._status[id] = OrderStatus.FULFILLED;
            // Clear order state
            delete $._orders[id];
            $._numOpenOrders--;
            // Notify order fulfilled
            emit OrderFulfilled(id, orderState.requester);
        } else {
            // Otherwise update order state
            uint256 feesPaid = orderState.feesPaid + feesEarned;
            // Check values
            if (!order.sell) {
                uint256 estimatedTotalFees = FeeLib.estimateTotalFees(
                    orderState.flatFee, orderState.percentageFeeRate, order.paymentTokenQuantity
                );
                assert(feesPaid <= estimatedTotalFees);
                // Update order escrow tracking
                if (order.escrowUnlocked) {
                    if (paymentEarned == 0) {
                        $._orders[id].escrowTaken -= fillAmount;
                    } else if (orderState.escrowTaken > 0) {
                        $._orders[id].escrowTaken = 0;
                    }
                }
            }
            $._orders[id].unfilledAmount = newUnfilledAmount;
            $._orders[id].received = orderState.received + receivedAmount;
            $._orders[id].feesPaid = feesPaid;
        }

        // ------------------ Interactions ------------------ //

        // Move tokens
        if (order.sell) {
            // update escrowed balance
            $._escrowedBalanceOf[order.assetToken][orderState.requester] -= fillAmount;
            // Burn the filled quantity from the asset token
            IDShare(order.assetToken).burn(fillAmount);

            // Transfer the received amount from the filler to this contract
            IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), receivedAmount);

            // If there are proceeds from the order, transfer them to the recipient
            IERC20(order.paymentToken).safeTransfer(order.recipient, paymentEarned);
        } else {
            // update escrowed balance
            $._escrowedBalanceOf[order.paymentToken][orderState.requester] -= paymentEarned + feesEarned;

            // Claim payment
            if (paymentEarned > 0) {
                IERC20(order.paymentToken).safeTransfer(msg.sender, paymentEarned);
            }

            // Mint asset
            IDShare(order.assetToken).mint(order.recipient, receivedAmount);
        }

        // If there are protocol fees from the order, transfer them to the treasury
        if (feesEarned > 0) {
            IERC20(order.paymentToken).safeTransfer($._treasury, feesEarned);
        }
    }

    /// @inheritdoc IOrderProcessor
    function cancelOrder(uint256 id, Order calldata order, string calldata reason) external onlyRole(OPERATOR_ROLE) {
        // ------------------ Checks ------------------ //

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        OrderState storage orderState = $._orders[id];
        address requester = orderState.requester;
        // Order must exist
        if (requester == address(0)) revert OrderNotFound();
        // Verify order data
        if (orderState.orderHash != hashOrder(order)) revert InvalidOrderData();
        // Prohibit cancel if escrowed payment has been taken and not returned or filled
        if (orderState.escrowTaken > 0) revert UnreturnedEscrow();

        // ------------------ Effects ------------------ //

        uint256 refund;
        if (order.sell) {
            refund = orderState.unfilledAmount;
        } else {
            uint256 totalFees =
                FeeLib.estimateTotalFees(orderState.flatFee, orderState.percentageFeeRate, order.paymentTokenQuantity);
            // If no fills, then full refund
            refund = orderState.unfilledAmount + totalFees;
            if (refund < order.paymentTokenQuantity + totalFees) {
                // Refund remaining order and fees
                refund -= orderState.feesPaid;
            }
        }

        // Order is cancelled
        $._status[id] = OrderStatus.CANCELLED;

        // Clear order state
        delete $._orders[id];
        $._numOpenOrders--;

        // Update user escrowed balance
        address refundToken = (order.sell) ? order.assetToken : order.paymentToken;
        $._escrowedBalanceOf[refundToken][requester] -= refund;

        // Notify order cancelled
        emit OrderCancelled(id, requester, reason);

        // ------------------ Interactions ------------------ //

        // Return escrow
        IERC20(refundToken).safeTransfer(requester, refund);
    }

    /// @notice Take escrowed payment for an order
    /// @param id order id
    /// @param order Order
    /// @param amount Amount of escrowed payment token to take
    /// @dev Only callable by operator
    function takeEscrow(uint256 id, Order calldata order, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        if (!order.escrowUnlocked) revert EscrowLocked();
        // Verify order data
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        OrderState storage orderState = $._orders[id];
        address requester = orderState.requester;
        // Order must exist
        if (requester == address(0)) revert OrderNotFound();
        // Verify order data
        if (orderState.orderHash != hashOrder(order)) revert InvalidOrderData();
        // Can't take more than available
        if (amount > orderState.unfilledAmount - orderState.escrowTaken) revert AmountTooLarge();

        // Update escrow tracking
        orderState.escrowTaken += amount;
        $._escrowedBalanceOf[order.paymentToken][requester] -= amount;

        // Notify escrow taken
        emit EscrowTaken(id, requester, amount);

        // Take escrowed payment
        IERC20(order.paymentToken).safeTransfer(msg.sender, amount);
    }

    /// @notice Return unused escrowed payment for an order
    /// @param id order id
    /// @param order Order
    /// @param amount Amount of payment token to return to escrow
    /// @dev Only callable by operator
    function returnEscrow(uint256 id, Order calldata order, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        if (!order.escrowUnlocked) revert EscrowLocked();
        // Verify order data
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        OrderState storage orderState = $._orders[id];
        address requester = orderState.requester;
        // Order must exist
        if (requester == address(0)) revert OrderNotFound();
        // Verify order data
        if (orderState.orderHash != hashOrder(order)) revert InvalidOrderData();
        // Can only return unused amount
        if (amount > orderState.escrowTaken) revert AmountTooLarge();

        // Update escrow tracking
        orderState.escrowTaken -= amount;
        $._escrowedBalanceOf[order.paymentToken][requester] += amount;

        // Notify escrow returned
        emit EscrowReturned(id, requester, amount);

        // Return payment to escrow
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), amount);
    }
}
