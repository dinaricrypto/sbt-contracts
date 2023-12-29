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
import {MulticallUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/MulticallUpgradeable.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {mulDiv, mulDiv18} from "prb-math/Common.sol";
import {SelfPermit} from "../common/SelfPermit.sol";
import {IOrderProcessor} from "./IOrderProcessor.sol";
import {ITransferRestrictor} from "../ITransferRestrictor.sol";
import {DShare, IDShare} from "../DShare.sol";
import {ITokenLockCheck} from "../ITokenLockCheck.sol";
import {FeeLib} from "../common/FeeLib.sol";
import {IForwarder} from "../forwarder/IForwarder.sol";

/// @notice Base contract managing orders for bridged assets
/// Orders are submitted by users, emitted by the contract, and filled by operators
/// Fees are accumulated as order is filled
/// The incoming token is escrowed until the order is filled or cancelled
/// The incoming token is refunded if the order is cancelled
/// Implicitly assumes that asset tokens are dShare and can be burned
/// Order lifecycle (fulfillment):
///   1. User requests an order (requestOrder)
///   2. [Optional] Operator partially fills the order (fillOrder)
///   3. Operator completely fulfills the order (fillOrder)
/// Order lifecycle (cancellation):
///   1. User requests an order (requestOrder)
///   2. [Optional] Operator partially fills the order (fillOrder)
///   3. [Optional] User requests cancellation (requestCancel)
///   4. Operator cancels the order (cancelOrder)
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/orders/OrderProcessor.sol)
contract OrderProcessor is
    Initializable,
    UUPSUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable,
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
        // Total fees paid to claim
        uint256 splitAmountPaid;
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

    /// @dev Zero address
    error ZeroAddress();
    /// @dev Orders are paused
    error Paused();
    /// @dev Zero value
    error ZeroValue();
    /// @dev msg.sender is not order requester
    error NotRequester();
    /// @dev Order does not exist
    error OrderNotFound();
    /// @dev Invalid order data
    error InvalidOrderData();
    /// @dev Amount too large
    error AmountTooLarge();
    /// @dev Order type mismatch
    error OrderTypeMismatch();
    error UnsupportedToken(address token);
    /// @dev blacklist address
    error Blacklist();
    /// @dev Custom error when an order cancellation has already been initiated
    error OrderCancellationInitiated();
    /// @dev Thrown when assetTokenQuantity's precision doesn't match the expected precision in orderDecimals.
    error InvalidPrecision();
    error LimitPriceNotSet();
    error OrderFillBelowLimitPrice();
    error OrderFillAboveLimitPrice();

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
    /// @notice Forwarder role for forwarding context awareness
    bytes32 public constant FORWARDER_ROLE = keccak256("FORWARDER_ROLE");

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

    /// @notice Has order cancellation been requested?
    /// @param id Order ID
    function cancelRequested(uint256 id) external view returns (bool) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._orders[id].cancellationInitiated;
    }

    function hasRole(bytes32 role, address account)
        public
        view
        override(AccessControlUpgradeable, IAccessControl, IOrderProcessor)
        returns (bool)
    {
        return super.hasRole(role, account);
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
    function requestOrder(Order calldata order) public whenOrdersNotPaused returns (uint256 id) {
        // cheap checks first
        if (order.recipient == address(0)) revert ZeroAddress();
        uint256 orderAmount = (order.sell) ? order.assetTokenQuantity : order.paymentTokenQuantity;
        // No zero orders
        if (orderAmount == 0) revert ZeroValue();
        if (order.splitAmount > 0 && order.splitRecipient == address(0)) revert ZeroAddress();

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
        // Cache order id
        id = $._nextOrderId;
        // Check requester
        address requester = getRequester(id);
        if (requester == address(0)) revert ZeroAddress();
        // black list checker
        blackListCheck(order.assetToken, order.paymentToken, order.recipient, requester);

        // Update next order id
        $._nextOrderId = id + 1;

        // Check values
        _requestOrderAccounting(id, order);

        // Send order to bridge
        emit OrderRequested(id, requester, order);

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
            cancellationInitiated: false,
            splitAmountPaid: 0
        });
        $._orderInfo[id] = OrderInfo({unfilledAmount: orderAmount, status: OrderStatus.ACTIVE});
        $._numOpenOrders++;

        if (order.sell) {
            // update escrowed balance
            $._escrowedBalanceOf[order.assetToken][order.recipient] += order.assetTokenQuantity;

            // Transfer asset to contract
            IERC20(order.assetToken).safeTransferFrom(msg.sender, address(this), order.assetTokenQuantity);
        } else {
            uint256 totalFees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, order.paymentTokenQuantity);
            uint256 quantityIn = order.paymentTokenQuantity + totalFees;
            // update escrowed balance
            $._escrowedBalanceOf[order.paymentToken][order.recipient] += quantityIn;

            // Escrow payment for purchase
            IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), quantityIn);
        }
    }

    function getRequester(uint256 id) internal view returns (address) {
        // Determine true requester
        if (hasRole(FORWARDER_ROLE, msg.sender)) {
            // If order was requested by a forwarder, use the forwarder's requester on file
            return IForwarder(msg.sender).orderSigner(id);
        }
        return msg.sender;
    }

    /// @notice Hash order data for validation
    function hashOrder(Order memory order) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                order.recipient,
                order.assetToken,
                order.paymentToken,
                order.sell,
                order.orderType,
                order.assetTokenQuantity,
                order.paymentTokenQuantity,
                order.price,
                order.tif,
                order.splitRecipient,
                order.splitAmount
            )
        );
    }

    /// @notice Hash order data for validation
    function hashOrderCalldata(Order calldata order) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                order.recipient,
                order.assetToken,
                order.paymentToken,
                order.sell,
                order.orderType,
                order.assetTokenQuantity,
                order.paymentTokenQuantity,
                order.price,
                order.tif,
                order.splitRecipient,
                order.splitAmount
            )
        );
    }

    /// @inheritdoc IOrderProcessor
    // slither-disable-next-line cyclomatic-complexity
    function fillOrder(uint256 id, Order calldata order, uint256 fillAmount, uint256 receivedAmount)
        external
        onlyRole(OPERATOR_ROLE)
    {
        // No nonsense
        if (fillAmount == 0) revert ZeroValue();

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        OrderState memory orderState = $._orders[id];

        // Order must exist
        if (orderState.requester == address(0)) revert OrderNotFound();
        // Verify order data
        if (orderState.orderHash != hashOrderCalldata(order)) revert InvalidOrderData();
        // Fill cannot exceed remaining order
        OrderInfo memory orderInfo = $._orderInfo[id];
        if (fillAmount > orderInfo.unfilledAmount) revert AmountTooLarge();

        // Calculate earned fees and handle any unique checks
        (uint256 paymentEarned, uint256 feesEarned) =
            _fillOrderAccounting(id, order, orderState, orderInfo.unfilledAmount, fillAmount, receivedAmount);

        // Notify order filled
        emit OrderFill(
            id, orderState.requester, order.paymentToken, order.assetToken, fillAmount, receivedAmount, feesEarned
        );

        // Take splitAmount from amount to distribute
        uint256 splitAmountEarned = 0;
        if (order.splitAmount > 0) {
            if (orderState.splitAmountPaid < order.splitAmount) {
                uint256 amountToDistribute = order.sell ? paymentEarned : receivedAmount;
                uint256 splitAmountRemaining = order.splitAmount - orderState.splitAmountPaid;
                if (amountToDistribute > splitAmountRemaining) {
                    splitAmountEarned = splitAmountRemaining;
                } else {
                    splitAmountEarned = amountToDistribute;
                }
            }
        }

        // Update order state
        _updateOrderStateForFill(
            id,
            orderInfo.unfilledAmount,
            orderState,
            order.sell,
            order.paymentTokenQuantity,
            fillAmount,
            receivedAmount,
            feesEarned,
            splitAmountEarned
        );

        // Move tokens
        if (order.sell) {
            // update escrowed balance
            $._escrowedBalanceOf[order.assetToken][order.recipient] -= fillAmount;
            // Burn the filled quantity from the asset token
            IDShare(order.assetToken).burn(fillAmount);

            // Transfer the received amount from the filler to this contract
            IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), receivedAmount);

            // Send split amount first
            if (splitAmountEarned > 0) {
                IERC20(order.paymentToken).safeTransfer(order.splitRecipient, splitAmountEarned);
            }

            // If there are proceeds from the order, transfer them to the recipient
            uint256 proceeds = paymentEarned - splitAmountEarned;
            if (proceeds > 0) {
                IERC20(order.paymentToken).safeTransfer(order.recipient, proceeds);
            }
        } else {
            // update escrowed balance
            $._escrowedBalanceOf[order.paymentToken][order.recipient] -= paymentEarned + feesEarned;
            // Claim payment
            IERC20(order.paymentToken).safeTransfer(msg.sender, paymentEarned);

            // Send split amount first
            if (splitAmountEarned > 0) {
                IDShare(order.assetToken).mint(order.recipient, splitAmountEarned);
            }

            // Mint asset
            uint256 proceeds = receivedAmount - splitAmountEarned;
            if (proceeds > 0) {
                IDShare(order.assetToken).mint(order.recipient, proceeds);
            }
        }

        // If there are protocol fees from the order, transfer them to the treasury
        if (feesEarned > 0) {
            IERC20(order.paymentToken).safeTransfer($._treasury, feesEarned);
        }
    }

    function _updateOrderStateForFill(
        uint256 id,
        uint256 unfilledAmount,
        OrderState memory orderState,
        bool sell,
        uint256 orderPaymentTokenQuantity,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256 feesEarned,
        uint256 splitAmountEarned
    ) private {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        uint256 newUnfilledAmount = unfilledAmount - fillAmount;
        $._orderInfo[id].unfilledAmount = newUnfilledAmount;
        // If order is completely filled then clear order state
        if (newUnfilledAmount == 0) {
            $._orderInfo[id].status = OrderStatus.FULFILLED;
            // Clear order state
            delete $._orders[id];
            $._numOpenOrders--;
            // Notify order fulfilled
            emit OrderFulfilled(id, orderState.requester);
        } else {
            // Otherwise update order state
            uint256 feesPaid = orderState.feesPaid + feesEarned;
            // Check values
            if (!sell) {
                uint256 estimatedTotalFees = FeeLib.estimateTotalFees(
                    orderState.flatFee, orderState.percentageFeeRate, orderPaymentTokenQuantity
                );
                assert(feesPaid <= estimatedTotalFees);
            }
            $._orders[id].received = orderState.received + receivedAmount;
            $._orders[id].feesPaid = feesPaid;
            if (splitAmountEarned > 0) {
                $._orders[id].splitAmountPaid = orderState.splitAmountPaid + splitAmountEarned;
            }
        }
    }

    function blackListCheck(address assetToken, address paymentToken, address recipient, address sender)
        internal
        view
    {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        ITokenLockCheck _tokenLockCheck = $._tokenLockCheck;
        if (_tokenLockCheck.isTransferLocked(assetToken, recipient)) revert Blacklist();
        if (_tokenLockCheck.isTransferLocked(assetToken, sender)) revert Blacklist();
        if (_tokenLockCheck.isTransferLocked(paymentToken, recipient)) revert Blacklist();
        if (_tokenLockCheck.isTransferLocked(paymentToken, sender)) revert Blacklist();
    }

    /// @notice Request to cancel an order
    /// @param id Order id
    /// @dev Only callable by initial order requester
    /// @dev Emits CancelRequested event to be sent to fulfillment service (operator)
    function requestCancel(uint256 id) external {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        if ($._orders[id].cancellationInitiated) revert OrderCancellationInitiated();
        // Order must exist
        address requester = $._orders[id].requester;
        if (requester == address(0)) revert OrderNotFound();
        // Get cancel requester
        address cancelRequester = getRequester(id);
        // Only requester can request cancellation
        if (requester != cancelRequester) revert NotRequester();

        $._orders[id].cancellationInitiated = true;

        // Send cancel request to bridge
        emit CancelRequested(id, requester);
    }

    /// @notice Cancel an order
    /// @param order Order to cancel
    /// @param id Order id
    /// @param reason Reason for cancellation
    /// @dev Only callable by operator
    function cancelOrder(uint256 id, Order calldata order, string calldata reason) external onlyRole(OPERATOR_ROLE) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        OrderState memory orderState = $._orders[id];
        // Order must exist
        if (orderState.requester == address(0)) revert OrderNotFound();
        // Verify order data
        if (orderState.orderHash != hashOrderCalldata(order)) revert InvalidOrderData();

        // Order is cancelled
        $._orderInfo[id].status = OrderStatus.CANCELLED;
        // Clear order state

        delete $._orders[id];
        $._numOpenOrders--;

        // Notify order cancelled
        emit OrderCancelled(id, orderState.requester, reason);

        // Calculate refund
        uint256 refund = _cancelOrderAccounting(id, order, orderState, $._orderInfo[id].unfilledAmount);

        address refundToken = (order.sell) ? order.assetToken : order.paymentToken;
        // update escrowed balance
        $._escrowedBalanceOf[refundToken][order.recipient] -= refund;

        // Return escrow
        IERC20(refundToken).safeTransfer(orderState.requester, refund);
    }

    /// ------------------ Virtuals ------------------ ///

    function _getOrderHash(uint256 id) internal view returns (bytes32) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._orders[id].orderHash;
    }

    function _getRequester(uint256 id) internal view returns (address) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._orders[id].requester;
    }

    function _increaseEscrowedBalanceOf(address token, address user, uint256 amount) internal {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._escrowedBalanceOf[token][user] += amount;
    }

    function _decreaseEscrowedBalanceOf(address token, address user, uint256 amount) internal {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._escrowedBalanceOf[token][user] -= amount;
    }

    /// @notice Perform any unique order request checks and accounting
    /// @param id Order ID
    /// @param order Order request to process
    function _requestOrderAccounting(uint256 id, Order calldata order) internal virtual {
        // Ensure that price is set for limit orders
        if (order.orderType == OrderType.LIMIT && order.price == 0) revert LimitPriceNotSet();
    }

    /// @notice Handle any unique order accounting and checks
    /// @param id Order ID
    /// @param order Order to fill
    /// @param orderState Order state
    /// @param unfilledAmount Amount of order token remaining to be used
    /// @param fillAmount Amount of order token filled
    /// @param receivedAmount Amount of received token
    /// @return paymentEarned Amount of payment token earned to be paid to operator or recipient
    /// @return feesEarned Amount of fees earned to be paid to treasury
    function _fillOrderAccounting(
        uint256 id,
        Order calldata order,
        OrderState memory orderState,
        uint256 unfilledAmount,
        uint256 fillAmount,
        uint256 receivedAmount
    ) internal virtual returns (uint256 paymentEarned, uint256 feesEarned) {
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

            paymentEarned = fillAmount;
            // Fees - earn the flat fee if first fill, then earn percentage fee on the fill
            feesEarned = 0;
            if (orderState.feesPaid == 0) {
                feesEarned = orderState.flatFee;
            }
            uint256 estimatedTotalFees =
                FeeLib.estimateTotalFees(orderState.flatFee, orderState.percentageFeeRate, order.paymentTokenQuantity);
            uint256 totalPercentageFees = estimatedTotalFees - orderState.flatFee;
            feesEarned += mulDiv(totalPercentageFees, fillAmount, order.paymentTokenQuantity);
        }
    }

    /// @notice Move tokens for order cancellation including fees and escrow
    /// @param id Order ID
    /// @param order Order to cancel
    /// @param orderState Order state
    /// @param unfilledAmount Amount of order token remaining to be used
    /// @return refund Amount of order token to refund to user
    function _cancelOrderAccounting(
        uint256 id,
        Order calldata order,
        OrderState memory orderState,
        uint256 unfilledAmount
    ) internal virtual returns (uint256 refund) {
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
    }
}
