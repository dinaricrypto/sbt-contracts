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
import {NoncesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/NoncesUpgradeable.sol";
import {MulticallUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/MulticallUpgradeable.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {mulDiv, mulDiv18} from "prb-math/Common.sol";
import {SelfPermit} from "../common/SelfPermit.sol";
import {IOrderProcessor} from "./IOrderProcessor.sol";
import {ITransferRestrictor} from "../ITransferRestrictor.sol";
import {DShare, IDShare} from "../DShare.sol";
import {ITokenLockCheck} from "../ITokenLockCheck.sol";
import {FeeLib} from "../common/FeeLib.sol";

/// @notice Core contract managing orders for dShare tokens
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/orders/OrderProcessor.sol)
// TODO: take non-refundable network fee in payment token
// TODO: reduce unnecessary storage reads
contract OrderProcessor is
    Initializable,
    UUPSUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable,
    NoncesUpgradeable,
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
        // Whether a cancellation for this order has been initiated
        bool cancellationInitiated;
        // Total amount of received token due to fills
        uint256 received;
        // Total fees paid to treasury
        uint256 feesPaid;
    }

    // Order state not cleared after order is fulfilled or cancelled.
    struct OrderInfo {
        // Amount of order token remaining to be used
        uint256 unfilledAmount;
        // Status of order
        OrderStatus status;
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
    /// @dev Order type mismatch
    error OrderTypeMismatch();
    error UnsupportedToken(address token);
    /// @dev blacklist address
    error Blacklist();
    error NotRequester();
    /// @dev Custom error when an order cancellation has already been initiated
    error OrderCancellationInitiated();
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

    /// ------------------ Constants ------------------ ///

    /// @notice Operator role for filling and cancelling orders
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @notice Asset token role for whitelisting asset tokens
    /// @dev Tokens with decimals > 18 are not supported by current implementation
    bytes32 public constant ASSETTOKEN_ROLE = keccak256("ASSETTOKEN_ROLE");

    bytes32 private constant ORDER_TYPEHASH = keccak256(
        "Order(address recipient,address assetToken,address paymentToken,bool sell,uint8 orderType,uint256 assetTokenQuantity,uint256 paymentTokenQuantity,uint256 price,uint8 tif)"
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
        // Persisted order state
        mapping(uint256 => OrderInfo) _orderInfo;
        // Escrowed balance of asset token per requester
        mapping(address => mapping(address => uint256)) _escrowedBalanceOf;
        // Max order decimals for asset token, defaults to 0 decimals
        mapping(address => int8) _maxOrderDecimals;
        // Fee schedule for requester, per paymentToken
        // Uses address(0) to store default fee schedule
        mapping(address => mapping(address => FeeRatesStorage)) _accountFees;
        // Order escrow tracking
        mapping(uint256 => uint256) _getOrderEscrow;
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
    function initialize(address _owner, address _treasury, ITokenLockCheck _tokenLockCheck)
        public
        virtual
        initializer
    {
        __AccessControlDefaultAdminRules_init(0, _owner);
        __Multicall_init();

        // Don't send fees to zero address
        if (_treasury == address(0)) revert ZeroAddress();

        // Initialize
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._treasury = _treasury;
        $._tokenLockCheck = _tokenLockCheck;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// ------------------ Getters ------------------ ///

    /// @notice Address to receive fees
    function treasury() public view returns (address) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._treasury;
    }

    /// @notice Transfer restrictor checker
    function tokenLockCheck() public view returns (ITokenLockCheck) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._tokenLockCheck;
    }

    /// @notice Are orders paused?
    function ordersPaused() public view returns (bool) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._ordersPaused;
    }

    /// @inheritdoc IOrderProcessor
    function numOpenOrders() public view override returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._numOpenOrders;
    }

    /// @inheritdoc IOrderProcessor
    function nextOrderId() public view override returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._nextOrderId;
    }

    /// @inheritdoc IOrderProcessor
    function escrowedBalanceOf(address token, address requester) public view override returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._escrowedBalanceOf[token][requester];
    }

    /// @inheritdoc IOrderProcessor
    function maxOrderDecimals(address token) public view override returns (int8) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._maxOrderDecimals[token];
    }

    /// @inheritdoc IOrderProcessor
    function getOrderStatus(uint256 id) external view returns (OrderStatus) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._orderInfo[id].status;
    }

    /// @inheritdoc IOrderProcessor
    function getUnfilledAmount(uint256 id) public view returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._orderInfo[id].unfilledAmount;
    }

    /// @inheritdoc IOrderProcessor
    function getTotalReceived(uint256 id) public view returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._orders[id].received;
    }

    /// @notice Get the amount of payment token escrowed for an order
    /// @param id order id
    function getOrderEscrow(uint256 id) external view returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._getOrderEscrow[id];
    }

    /// @notice Has order cancellation been requested?
    /// @param id Order ID
    function cancelRequested(uint256 id) external view returns (bool) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._orders[id].cancellationInitiated;
    }

    function getAccountFees(address account, address paymentToken) external view returns (FeeRates memory) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        FeeRatesStorage memory feeRates = $._accountFees[account][paymentToken];
        // If user,paymentToken does not have a custom fee schedule, use default
        if (!feeRates.set) {
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
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        FeeRatesStorage memory feeRates = $._accountFees[requester][paymentToken];
        // If user does not have a custom fee schedule, use default
        if (!feeRates.set) {
            feeRates = $._accountFees[address(0)][paymentToken];
        }
        if (sell) {
            return (FeeLib.flatFeeForOrder(paymentToken, feeRates.perOrderFeeSell), feeRates.percentageFeeRateSell);
        } else {
            return (FeeLib.flatFeeForOrder(paymentToken, feeRates.perOrderFeeBuy), feeRates.percentageFeeRateBuy);
        }
    }

    /// @inheritdoc IOrderProcessor
    function estimateTotalFeesForOrder(
        address requester,
        bool sell,
        address paymentToken,
        uint256 paymentTokenOrderValue
    ) public view returns (uint256) {
        // Get fee rates
        (uint256 flatFee, uint24 percentageFeeRate) = getFeeRatesForOrder(requester, sell, paymentToken);
        // Calculate total fees
        return FeeLib.estimateTotalFees(flatFee, percentageFeeRate, paymentTokenOrderValue);
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

    /// @notice Set default fee rates
    /// @param paymentToken Payment token
    /// @param feeRates Fee rates
    /// @dev Only callable by admin
    function setDefaultFees(address paymentToken, FeeRates memory feeRates) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFees(address(0), paymentToken, feeRates);
    }

    /// @notice Set unique fee rates for requester
    /// @param requester Requester address
    /// @param paymentToken Payment token
    /// @param feeRates Fee rates
    /// @dev Only callable by admin
    function setFees(address requester, address paymentToken, FeeRates memory feeRates)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (requester == address(0)) revert ZeroAddress();
        _setFees(requester, paymentToken, feeRates);
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

    function _setFees(address account, address paymentToken, FeeRates memory feeRates) private {
        FeeLib.checkPercentageFeeRate(feeRates.percentageFeeRateBuy);
        FeeLib.checkPercentageFeeRate(feeRates.percentageFeeRateSell);

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._accountFees[account][paymentToken] = FeeRatesStorage({
            set: true,
            perOrderFeeBuy: feeRates.perOrderFeeBuy,
            percentageFeeRateBuy: feeRates.percentageFeeRateBuy,
            perOrderFeeSell: feeRates.perOrderFeeSell,
            percentageFeeRateSell: feeRates.percentageFeeRateSell
        });
        emit FeesSet(account, paymentToken, feeRates);
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

    /// ------------------ Order Lifecycle ------------------ ///

    /// @inheritdoc IOrderProcessor
    function pullPaymentForSignedOrder(Order calldata order, Signature calldata signature)
        public
        whenOrdersNotPaused
        onlyRole(OPERATOR_ROLE)
        returns (uint256 id)
    {
        address requester = _validateOrderSignature(order, signature);
        id = _initializeOrder(order, requester);
    }

    /// @dev Recover requester and validate signature
    function _validateOrderSignature(Order calldata order, Signature calldata signature)
        private
        returns (address requester)
    {
        if (signature.deadline < block.timestamp) revert ExpiredSignature();
        // Recover order requester
        requester = ECDSA.recover(hashOrderRequest(order, signature.deadline, signature.nonce), signature.signature);
        _useCheckedNonce(requester, signature.nonce);
    }

    /// @dev Validate order, initialize order state, and pull tokens
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

        // Precision checked for assetTokenQuantity, market buys excluded
        if (order.sell || order.orderType == OrderType.LIMIT) {
            // Check for max order decimals (assetTokenQuantity)
            uint8 assetTokenDecimals = IERC20Metadata(order.assetToken).decimals();
            uint256 assetPrecision = 10 ** uint8(int8(assetTokenDecimals) - $._maxOrderDecimals[order.assetToken]);
            if (order.assetTokenQuantity % assetPrecision != 0) revert InvalidPrecision();
        }

        // Check for whitelisted tokens
        if (!hasRole(ASSETTOKEN_ROLE, order.assetToken)) revert UnsupportedToken(order.assetToken);
        if (!$._accountFees[address(0)][order.paymentToken].set) revert UnsupportedToken(order.paymentToken);

        // black list checker
        ITokenLockCheck _tokenLockCheck = $._tokenLockCheck;
        if (_tokenLockCheck.isTransferLocked(order.assetToken, order.recipient)) revert Blacklist();
        if (_tokenLockCheck.isTransferLocked(order.assetToken, requester)) revert Blacklist();
        if (_tokenLockCheck.isTransferLocked(order.paymentToken, order.recipient)) revert Blacklist();
        if (_tokenLockCheck.isTransferLocked(order.paymentToken, requester)) revert Blacklist();

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
            received: 0,
            feesPaid: 0,
            cancellationInitiated: false
        });
        $._orderInfo[id] = OrderInfo({unfilledAmount: orderAmount, status: OrderStatus.ACTIVE});
        $._numOpenOrders++;

        // Initialize payment escrow tracking for buy order
        if (order.escrowUnlocked) {
            $._getOrderEscrow[id] = order.paymentTokenQuantity;
        }

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

    /// @inheritdoc IOrderProcessor
    function requestOrder(Order calldata order) public whenOrdersNotPaused returns (uint256 id) {
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
                order.tif
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
        OrderInfo memory orderInfo = $._orderInfo[id];
        if (fillAmount > orderInfo.unfilledAmount) revert AmountTooLarge();

        // Calculate earned fees and handle any unique checks
        uint256 paymentEarned;
        uint256 feesEarned;
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
                uint256 escrowTaken = orderInfo.unfilledAmount - $._getOrderEscrow[id];
                if (fillAmount > escrowTaken) {
                    paymentEarned = fillAmount - escrowTaken;
                } else {
                    paymentEarned = 0;
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
        uint256 newUnfilledAmount = orderInfo.unfilledAmount - fillAmount;
        $._orderInfo[id].unfilledAmount = newUnfilledAmount;
        // If order is completely filled then clear order state
        if (newUnfilledAmount == 0) {
            $._orderInfo[id].status = OrderStatus.FULFILLED;
            // Clear order state
            delete $._orders[id];
            $._numOpenOrders--;
            delete $._getOrderEscrow[id];
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
                if (order.escrowUnlocked && paymentEarned > 0) {
                    $._getOrderEscrow[id] -= paymentEarned;
                }
            }
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
    function requestCancel(uint256 id) external {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        if ($._orders[id].cancellationInitiated) revert OrderCancellationInitiated();
        // Order must exist
        address requester = $._orders[id].requester;
        if (requester == address(0)) revert OrderNotFound();
        // Only requester can request cancellation
        if (requester != msg.sender) revert NotRequester();

        $._orders[id].cancellationInitiated = true;

        // Send cancel request to bridge
        emit CancelRequested(id, requester);
    }

    /// @inheritdoc IOrderProcessor
    function cancelOrder(uint256 id, Order calldata order, string calldata reason) external onlyRole(OPERATOR_ROLE) {
        // ------------------ Checks ------------------ //

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        OrderState memory orderState = $._orders[id];
        // Order must exist
        if (orderState.requester == address(0)) revert OrderNotFound();
        // Verify order data
        if (orderState.orderHash != hashOrder(order)) revert InvalidOrderData();
        // Prohibit cancel if escrowed payment has been taken and not returned or filled
        uint256 unfilledAmount = $._orderInfo[id].unfilledAmount;
        if (order.escrowUnlocked && unfilledAmount != $._getOrderEscrow[id]) revert UnreturnedEscrow();

        // ------------------ Effects ------------------ //

        // Order is cancelled
        $._orderInfo[id].status = OrderStatus.CANCELLED;

        // Clear order state
        delete $._orders[id];
        $._numOpenOrders--;
        // Clear the order escrow record
        delete $._getOrderEscrow[id];

        uint256 refund;
        if (order.sell) {
            refund = unfilledAmount;
        } else {
            uint256 totalFees =
                FeeLib.estimateTotalFees(orderState.flatFee, orderState.percentageFeeRate, order.paymentTokenQuantity);
            // If no fills, then full refund
            refund = unfilledAmount + totalFees;
            if (refund < order.paymentTokenQuantity + totalFees) {
                // Refund remaining order and fees
                refund -= orderState.feesPaid;
            }
        }

        // Update user escrowed balance
        address refundToken = (order.sell) ? order.assetToken : order.paymentToken;
        $._escrowedBalanceOf[refundToken][orderState.requester] -= refund;

        // Notify order cancelled
        emit OrderCancelled(id, orderState.requester, reason);

        // ------------------ Interactions ------------------ //

        // Return escrow
        IERC20(refundToken).safeTransfer(orderState.requester, refund);
    }

    /// @notice Take escrowed payment for an order
    /// @param id order id
    /// @param order Order
    /// @param amount Amount of escrowed payment token to take
    /// @dev Only callable by operator
    function takeEscrow(uint256 id, Order calldata order, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        // No nonsense
        if (amount == 0) revert ZeroValue();
        if (!order.escrowUnlocked) revert EscrowLocked();
        // Verify order data
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        OrderState memory orderState = $._orders[id];
        // Order must exist
        if (orderState.requester == address(0)) revert OrderNotFound();
        // Verify order data
        if (orderState.orderHash != hashOrder(order)) revert InvalidOrderData();
        // Can't take more than escrowed
        uint256 escrow = $._getOrderEscrow[id];
        if (amount > escrow) revert AmountTooLarge();

        // Update escrow tracking
        $._getOrderEscrow[id] = escrow - amount;
        $._escrowedBalanceOf[order.paymentToken][orderState.requester] -= amount;

        // Notify escrow taken
        emit EscrowTaken(id, orderState.requester, amount);

        // Take escrowed payment
        IERC20(order.paymentToken).safeTransfer(msg.sender, amount);
    }

    /// @notice Return unused escrowed payment for an order
    /// @param id order id
    /// @param order Order
    /// @param amount Amount of payment token to return to escrow
    /// @dev Only callable by operator
    function returnEscrow(uint256 id, Order calldata order, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        // No nonsense
        if (amount == 0) revert ZeroValue();
        if (!order.escrowUnlocked) revert EscrowLocked();
        // Verify order data
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        OrderState memory orderState = $._orders[id];
        // Order must exist
        if (orderState.requester == address(0)) revert OrderNotFound();
        // Verify order data
        if (orderState.orderHash != hashOrder(order)) revert InvalidOrderData();
        // Can only return unused amount
        uint256 escrow = $._getOrderEscrow[id];
        // Unused amount = remaining order - remaining escrow
        if (escrow + amount > $._orderInfo[id].unfilledAmount) revert AmountTooLarge();

        // Update escrow tracking
        $._getOrderEscrow[id] = escrow + amount;
        $._escrowedBalanceOf[order.paymentToken][orderState.requester] += amount;

        // Notify escrow returned
        emit EscrowReturned(id, orderState.requester, amount);

        // Return payment to escrow
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), amount);
    }
}
