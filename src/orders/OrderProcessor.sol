// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {
    UUPSUpgradeable,
    Initializable
} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {EIP712Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/cryptography/EIP712Upgradeable.sol";
import {MulticallUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/MulticallUpgradeable.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {mulDiv, mulDiv18} from "prb-math/Common.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {SelfPermit} from "../common/SelfPermit.sol";
import {IOrderProcessor} from "./IOrderProcessor.sol";
import {IDShare} from "../IDShare.sol";
import {ITokenLockCheck} from "../ITokenLockCheck.sol";
import {FeeLib} from "../common/FeeLib.sol";
import {IDShareFactory} from "../IDShareFactory.sol";

/// @notice Core contract managing orders for dShare tokens
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/orders/OrderProcessor.sol)
contract OrderProcessor is
    Initializable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    EIP712Upgradeable,
    MulticallUpgradeable,
    SelfPermit,
    IOrderProcessor
{
    using SafeERC20 for IERC20;

    /// ------------------ Types ------------------ ///

    // Order state cleared after order is fulfilled or cancelled.
    struct OrderState {
        // Flat fee at time of order request including applied network fee
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
    error NotOperator();
    error NotRequester();

    /// @dev Emitted when `treasury` is set
    event TreasurySet(address indexed treasury);
    /// @dev Emitted when orders are paused/unpaused
    event OrdersPaused(bool paused);
    /// @dev Emitted when token lock check contract is set
    event TokenLockCheckSet(ITokenLockCheck indexed tokenLockCheck);
    /// @dev Emitted when fees are set
    event FeesSet(
        address indexed account,
        address indexed paymentToken,
        uint64 perOrderFeeBuy,
        uint24 percentageFeeRateBuy,
        uint64 perOrderFeeSell,
        uint24 percentageFeeRateSell
    );
    event FeesReset(address indexed account, address indexed paymentToken);
    /// @dev Emitted when OrderDecimal is set
    event MaxOrderDecimalsSet(address indexed assetToken, int8 decimals);
    event EthUsdOracleSet(address indexed ethUsdOracle);
    event PaymentTokenOracleSet(address indexed paymentToken, address indexed oracle);
    event OperatorSet(address indexed account, bool status);

    /// ------------------ Constants ------------------ ///

    bytes32 private constant ORDER_TYPEHASH = keccak256(
        "Order(uint256 salt,address recipient,address assetToken,address paymentToken,bool sell,uint8 orderType,uint256 assetTokenQuantity,uint256 paymentTokenQuantity,uint256 price,uint8 tif)"
    );

    bytes32 private constant ORDER_REQUEST_TYPEHASH =
        keccak256("OrderRequest(uint256 id,uint256 deadline,uint256 nonce)");

    /// ------------------ State ------------------ ///

    struct OrderProcessorStorage {
        // Address to receive fees
        address _treasury;
        // Address of payment vault
        address _vault;
        // DShareFactory contract
        IDShareFactory _dShareFactory;
        // Transfer restrictor checker
        ITokenLockCheck _tokenLockCheck;
        // Are orders paused?
        bool _ordersPaused;
        // Total number of active orders. Onchain enumeration not supported.
        uint256 _numOpenOrders;
        // Operators for filling and cancelling orders
        mapping(address => bool) _operators;
        // Active order state
        mapping(uint256 => OrderState) _orders;
        // Status of order
        mapping(uint256 => OrderStatus) _status;
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
    /// @param _vault Address of vault contract
    /// @param _dShareFactory DShareFactory contract
    /// @param _tokenLockCheck Token lock check contract
    /// @param _ethUsdOracle ETH USD price oracle
    /// @dev Treasury cannot be zero address
    function initialize(
        address _owner,
        address _treasury,
        address _vault,
        IDShareFactory _dShareFactory,
        ITokenLockCheck _tokenLockCheck,
        address _ethUsdOracle
    ) public virtual initializer {
        __Ownable_init(_owner);
        __EIP712_init("OrderProcessor", "1");
        __Multicall_init();

        // Don't send fees to zero address
        if (_treasury == address(0)) revert ZeroAddress();
        if (_vault == address(0)) revert ZeroAddress();
        if (address(_dShareFactory) == address(0)) revert ZeroAddress();
        if (_ethUsdOracle == address(0)) revert ZeroAddress();

        // Initialize
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._treasury = _treasury;
        $._vault = _vault;
        $._dShareFactory = _dShareFactory;
        $._tokenLockCheck = _tokenLockCheck;
        $._ethUsdOracle = _ethUsdOracle;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// ------------------ Getters ------------------ ///

    /// @notice Address to receive fees
    function treasury() external view returns (address) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._treasury;
    }

    /// @notice Address of vault contract
    function vault() external view returns (address) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._vault;
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

    function isOperator(address account) external view returns (bool) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._operators[account];
    }

    /// @inheritdoc IOrderProcessor
    function numOpenOrders() external view override returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._numOpenOrders;
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

    function getAccountFees(address requester, address paymentToken)
        public
        view
        returns (
            uint64 perOrderFeeBuy,
            uint24 percentageFeeRateBuy,
            uint64 perOrderFeeSell,
            uint24 percentageFeeRateSell
        )
    {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        FeeRatesStorage storage feeRatesPointer = $._accountFees[requester][paymentToken];
        // If user, paymentToken does not have a custom fee schedule, use default
        FeeRatesStorage memory feeRates;
        if (feeRatesPointer.set) {
            feeRates = feeRatesPointer;
        } else {
            feeRates = $._accountFees[address(0)][paymentToken];
        }
        return (
            feeRates.perOrderFeeBuy,
            feeRates.percentageFeeRateBuy,
            feeRates.perOrderFeeSell,
            feeRates.percentageFeeRateSell
        );
    }

    /// @inheritdoc IOrderProcessor
    function getFeeRatesForOrder(address requester, bool sell, address paymentToken)
        public
        view
        returns (uint256, uint24)
    {
        (uint64 perOrderFeeBuy, uint24 percentageFeeRateBuy, uint64 perOrderFeeSell, uint24 percentageFeeRateSell) =
            getAccountFees(requester, paymentToken);
        if (sell) {
            return (FeeLib.flatFeeForOrder(paymentToken, perOrderFeeSell), percentageFeeRateSell);
        } else {
            return (FeeLib.flatFeeForOrder(paymentToken, perOrderFeeBuy), percentageFeeRateBuy);
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

    modifier onlyOperator() {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        if (!$._operators[msg.sender]) revert NotOperator();
        _;
    }

    /// @notice Set treasury address
    /// @param account Address to receive fees
    /// @dev Only callable by admin
    /// Treasury cannot be zero address
    function setTreasury(address account) external onlyOwner {
        // Don't send fees to zero address
        if (account == address(0)) revert ZeroAddress();

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._treasury = account;
        emit TreasurySet(account);
    }

    /// @notice Set vault address
    /// @param account Address of vault contract
    /// @dev Only callable by admin
    /// Vault cannot be zero address
    function setVault(address account) external onlyOwner {
        // Don't send tokens to zero address
        if (account == address(0)) revert ZeroAddress();

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._vault = account;
    }

    /// @notice Pause/unpause orders
    /// @param pause Pause orders if true, unpause if false
    /// @dev Only callable by admin
    function setOrdersPaused(bool pause) external onlyOwner {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._ordersPaused = pause;
        emit OrdersPaused(pause);
    }

    /// @notice Set token lock check contract
    /// @param _tokenLockCheck Token lock check contract
    /// @dev Only callable by admin
    function setTokenLockCheck(ITokenLockCheck _tokenLockCheck) external onlyOwner {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._tokenLockCheck = _tokenLockCheck;
        emit TokenLockCheckSet(_tokenLockCheck);
    }

    /// @notice Set operator
    /// @param account Operator address
    /// @param status Operator status
    /// @dev Only callable by admin
    function setOperator(address account, bool status) external onlyOwner {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._operators[account] = status;
        emit OperatorSet(account, status);
    }

    /// @notice Set unique fee rates for requester and payment token
    /// @dev Only callable by admin, set zero address to set default
    function setFees(
        address requester,
        address paymentToken,
        uint64 perOrderFeeBuy,
        uint24 percentageFeeRateBuy,
        uint64 perOrderFeeSell,
        uint24 percentageFeeRateSell
    ) external onlyOwner {
        FeeLib.checkPercentageFeeRate(percentageFeeRateBuy);
        FeeLib.checkPercentageFeeRate(percentageFeeRateSell);
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        if (requester != address(0) && !$._accountFees[address(0)][paymentToken].set) {
            revert UnsupportedToken(paymentToken);
        }

        $._accountFees[requester][paymentToken] = FeeRatesStorage({
            set: true,
            perOrderFeeBuy: perOrderFeeBuy,
            percentageFeeRateBuy: percentageFeeRateBuy,
            perOrderFeeSell: perOrderFeeSell,
            percentageFeeRateSell: percentageFeeRateSell
        });
        emit FeesSet(
            requester, paymentToken, perOrderFeeBuy, percentageFeeRateBuy, perOrderFeeSell, percentageFeeRateSell
        );
    }

    /// @notice Reset fee rates for requester to default
    /// @param requester Requester address
    /// @param paymentToken Payment token
    /// @dev Only callable by admin
    function resetFees(address requester, address paymentToken) external onlyOwner {
        if (requester == address(0)) revert ZeroAddress();

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        delete $._accountFees[requester][paymentToken];
        emit FeesReset(requester, paymentToken);
    }

    /// @notice Set max order decimals for asset token
    /// @param token Asset token
    /// @param decimals Max order decimals
    /// @dev Only callable by admin
    function setMaxOrderDecimals(address token, int8 decimals) external onlyOwner {
        uint8 tokenDecimals = IERC20Metadata(token).decimals();
        if (decimals > int8(tokenDecimals)) revert InvalidPrecision();
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._maxOrderDecimals[token] = decimals;
        emit MaxOrderDecimalsSet(token, decimals);
    }

    function setEthUsdOracle(address _ethUsdOracle) external onlyOwner {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._ethUsdOracle = _ethUsdOracle;
        emit EthUsdOracleSet(_ethUsdOracle);
    }

    function setPaymentTokenOracle(address paymentToken, address oracle) external onlyOwner {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._paymentTokenOracle[paymentToken] = oracle;
        emit PaymentTokenOracleSet(paymentToken, oracle);
    }

    /// ------------------ Order Lifecycle ------------------ ///

    /// @inheritdoc IOrderProcessor
    function createOrderWithSignature(Order calldata order, Signature calldata signature)
        external
        whenOrdersNotPaused
        onlyOperator
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
        id = _createOrder(order, requester);

        // Pull payment for order creation
        uint256 tokenPriceInWei = _getTokenPriceInWei(_oracle);

        // Charge user for gas fees
        uint256 networkFee = 0;
        {
            uint256 gasUsed = gasStart - gasleft();
            uint256 gasCostInWei = gasUsed * tx.gasprice;

            // Apply payment token price to calculate payment amount
            // Assumes payment token price includes token decimals
            try IERC20Metadata(order.paymentToken).decimals() returns (uint8 tokenDecimals) {
                networkFee = gasCostInWei * 10 ** tokenDecimals / tokenPriceInWei;
            } catch {
                networkFee = gasCostInWei / tokenPriceInWei;
            }
        }

        // Record or transfer the payment for gas fees
        if (order.sell) {
            // Add network fee to flat fee taken from proceeds
            $._orders[id].flatFee += networkFee;
        } else {
            // Pull payment for gas fees
            IERC20(order.paymentToken).safeTransferFrom(requester, $._vault, networkFee);
        }
    }

    /// @dev Validate order, initialize order state, and pull tokens
    // slither-disable-next-line cyclomatic-complexity
    function _createOrder(Order calldata order, address requester) private returns (uint256 id) {
        // ------------------ Checks ------------------ //

        // Cheap checks first
        if (order.recipient == address(0)) revert ZeroAddress();
        uint256 orderAmount = (order.sell) ? order.assetTokenQuantity : order.paymentTokenQuantity;
        // No zero orders
        if (orderAmount == 0) revert ZeroValue();
        // Ensure that price is set for limit orders
        if (order.orderType == OrderType.LIMIT && order.price == 0) revert LimitPriceNotSet();

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();

        // Order must not exist
        id = hashOrder(order);
        if ($._status[id] != OrderStatus.NONE) revert InvalidOrderData();

        // Check for whitelisted tokens
        if (!$._dShareFactory.isTokenDShare(order.assetToken)) revert UnsupportedToken(order.assetToken);
        if (!$._accountFees[address(0)][order.paymentToken].set) revert UnsupportedToken(order.paymentToken);

        // Precision checked for assetTokenQuantity, market buys excluded
        if (order.sell || order.orderType == OrderType.LIMIT) {
            // Check for max order decimals (assetTokenQuantity)
            uint8 assetTokenDecimals = IERC20Metadata(order.assetToken).decimals();
            uint256 assetPrecision = 10 ** uint8(int8(assetTokenDecimals) - $._maxOrderDecimals[order.assetToken]);
            if (order.assetTokenQuantity % assetPrecision != 0) revert InvalidPrecision();
        }

        // Black list checker
        // TODO: Try moving stored calls here to reduce cost of external call
        ITokenLockCheck _tokenLockCheck = $._tokenLockCheck;
        if (
            _tokenLockCheck.isTransferLocked(order.assetToken, order.recipient)
                || _tokenLockCheck.isTransferLocked(order.assetToken, requester)
                || _tokenLockCheck.isTransferLocked(order.paymentToken, order.recipient)
                || _tokenLockCheck.isTransferLocked(order.paymentToken, requester)
        ) revert Blacklist();

        // ------------------ Effects ------------------ //

        // Calculate fees
        (uint256 flatFee, uint24 percentageFeeRate) = getFeeRatesForOrder(requester, order.sell, order.paymentToken);
        // Initialize order state
        $._orders[id] = OrderState({
            requester: requester,
            flatFee: flatFee,
            percentageFeeRate: percentageFeeRate,
            unfilledAmount: orderAmount,
            received: 0,
            feesPaid: 0
        });
        $._status[id] = OrderStatus.ACTIVE;
        $._numOpenOrders++;

        emit OrderCreated(id, requester);

        // ------------------ Interactions ------------------ //

        // Move funds to vault for buys, burn assets for sells
        if (order.sell) {
            // Burn asset
            IDShare(order.assetToken).burnFrom(requester, order.assetTokenQuantity);
        } else {
            uint256 orderFees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, order.paymentTokenQuantity);

            // Sweep payment for purchase
            IERC20(order.paymentToken).safeTransferFrom(requester, $._vault, order.paymentTokenQuantity);
            // Escrow fees
            IERC20(order.paymentToken).safeTransferFrom(requester, address(this), orderFees);
        }
    }

    /**
     * @notice Get the current oracle price for a payment token
     */
    function getTokenPriceInWei(address paymentToken) external view returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return _getTokenPriceInWei($._paymentTokenOracle[paymentToken]);
    }

    function _getTokenPriceInWei(address _paymentTokenOracle) internal view returns (uint256) {
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

    /// @inheritdoc IOrderProcessor
    function requestOrder(Order calldata order) external whenOrdersNotPaused returns (uint256 id) {
        id = _createOrder(order, msg.sender);

        // Send order to bridge
        emit OrderRequested(id, msg.sender, order);
    }

    function hashOrderRequest(Order calldata order, uint256 deadline, uint256 nonce) public pure returns (bytes32) {
        return keccak256(abi.encode(ORDER_REQUEST_TYPEHASH, hashOrder(order), deadline, nonce));
    }

    /// @inheritdoc IOrderProcessor
    function hashOrder(Order calldata order) public pure returns (uint256) {
        return uint256(
            keccak256(
                abi.encode(
                    ORDER_TYPEHASH,
                    order.salt,
                    order.recipient,
                    order.assetToken,
                    order.paymentToken,
                    order.sell,
                    order.orderType,
                    order.assetTokenQuantity,
                    order.paymentTokenQuantity,
                    order.price,
                    order.tif
                )
            )
        );
    }

    /// @inheritdoc IOrderProcessor
    // slither-disable-next-line cyclomatic-complexity
    function fillOrder(uint256 id, Order calldata order, uint256 fillAmount, uint256 receivedAmount)
        external
        onlyOperator
    {
        // ------------------ Checks ------------------ //

        // No nonsense
        if (fillAmount == 0) revert ZeroValue();
        // Verify order data
        if (id != hashOrder(order)) revert InvalidOrderData();

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        OrderState memory orderState = $._orders[id];

        // Order must exist
        if (orderState.requester == address(0)) revert OrderNotFound();
        // Fill cannot exceed remaining order
        if (fillAmount > orderState.unfilledAmount) revert AmountTooLarge();

        // Calculate earned fees and handle any unique checks
        uint256 feesEarned = 0;
        uint256 estimatedTotalFees = 0;
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
            estimatedTotalFees =
                orderState.flatFee + FeeLib.applyPercentageFee(orderState.percentageFeeRate, order.paymentTokenQuantity);
            uint256 totalPercentageFees = estimatedTotalFees - orderState.flatFee;
            feesEarned += mulDiv(totalPercentageFees, fillAmount, order.paymentTokenQuantity);
        }

        // ------------------ Effects ------------------ //

        // Notify order filled
        emit OrderFill(
            id,
            order.paymentToken,
            order.assetToken,
            orderState.requester,
            order.sell ? receivedAmount : fillAmount,
            order.sell ? fillAmount : receivedAmount,
            feesEarned,
            order.sell
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
                assert(feesPaid <= estimatedTotalFees);
            }
            $._orders[id].unfilledAmount = newUnfilledAmount;
            $._orders[id].received = orderState.received + receivedAmount;
            $._orders[id].feesPaid = feesPaid;
        }

        // ------------------ Interactions ------------------ //

        // Move funds from operator for sells, mint assets for buys
        if (order.sell) {
            // Transfer the received amount from the filler to this contract
            IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), receivedAmount);

            // If there are proceeds from the order, transfer them to the recipient
            uint256 paymentEarned = receivedAmount - feesEarned;
            if (paymentEarned > 0) {
                IERC20(order.paymentToken).safeTransfer(order.recipient, paymentEarned);
            }
        } else {
            // Mint asset
            IDShare(order.assetToken).mint(order.recipient, receivedAmount);
        }

        // If there are protocol fees from the order, transfer them to the treasury
        if (feesEarned > 0) {
            IERC20(order.paymentToken).safeTransfer($._treasury, feesEarned);
        }
    }

    /// @inheritdoc IOrderProcessor
    function requestCancel(uint256 id) external {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        // Order must exist
        address requester = $._orders[id].requester;
        if (requester == address(0)) revert OrderNotFound();
        // Only requester can request cancellation
        if (requester != msg.sender) revert NotRequester();

        // Send cancel request to bridge
        emit CancelRequested(id, requester);
    }

    /// @inheritdoc IOrderProcessor
    function cancelOrder(uint256 id, Order calldata order, string calldata reason) external onlyOperator {
        // ------------------ Checks ------------------ //

        // Verify order data
        if (id != hashOrder(order)) revert InvalidOrderData();

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        OrderState storage orderState = $._orders[id];
        address requester = orderState.requester;
        // Order must exist
        if (requester == address(0)) revert OrderNotFound();

        // ------------------ Effects ------------------ //

        uint256 feeRefund = 0;
        if (!order.sell) {
            // If no fills, then full refund
            feeRefund =
                orderState.flatFee + FeeLib.applyPercentageFee(orderState.percentageFeeRate, order.paymentTokenQuantity);
            if (orderState.unfilledAmount < order.paymentTokenQuantity) {
                // Refund remaining order and fees
                feeRefund -= orderState.feesPaid;
            }
        }
        uint256 unfilledAmount = orderState.unfilledAmount;

        // Order is cancelled
        $._status[id] = OrderStatus.CANCELLED;

        // Clear order state
        delete $._orders[id];
        $._numOpenOrders--;

        // Notify order cancelled
        emit OrderCancelled(id, requester, reason);

        // ------------------ Interactions ------------------ //

        // Return escrowed fees and unfilled amount
        if (order.sell) {
            // Mint unfilled
            IDShare(order.assetToken).mint(requester, unfilledAmount);
        } else {
            // Return unfilled
            IERC20(order.paymentToken).safeTransferFrom(msg.sender, requester, unfilledAmount);
            IERC20(order.paymentToken).safeTransfer(requester, feeRefund);
        }
    }
}
