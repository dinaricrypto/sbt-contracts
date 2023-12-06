// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {
    AccessControlDefaultAdminRules,
    AccessControl,
    IAccessControl
} from "openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import {SelfPermit} from "../common/SelfPermit.sol";
import {IOrderProcessor} from "./IOrderProcessor.sol";
import {ITransferRestrictor} from "../ITransferRestrictor.sol";
import {dShare} from "../dShare.sol";
import {ITokenLockCheck} from "../ITokenLockCheck.sol";
import {IdShare} from "../IdShare.sol";
import {FeeLib} from "../common/FeeLib.sol";
import {IForwarder} from "../forwarder/IForwarder.sol";
import {IFeeSchedule} from "./IFeeSchedule.sol";

/// @notice Base contract managing orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/orders/OrderProcessor.sol)
/// Orders are submitted by users and filled by operators
/// Handling of fees is left to the inheriting contract
/// Each inheritor can craft a unique order processing flow
/// It is recommended that implementations offer a single process for all orders
///   This maintains clarity for users and for interpreting contract token balances
/// Specifies a generic order request struct such that
///   inheriting contracts must implement unique request methods to handle multiple order processes simultaneously
/// Order lifecycle (fulfillment):
///   1. User requests an order (requestOrder)
///   2. [Optional] Operator partially fills the order (fillOrder)
///   3. Operator completely fulfills the order (fillOrder)
/// Order lifecycle (cancellation):
///   1. User requests an order (requestOrder)
///   2. [Optional] Operator partially fills the order (fillOrder)
///   3. [Optional] User requests cancellation (requestCancel)
///   4. Operator cancels the order (cancelOrder)
abstract contract OrderProcessor is AccessControlDefaultAdminRules, Multicall, SelfPermit, IOrderProcessor {
    using SafeERC20 for IERC20;

    /// ------------------ Types ------------------ ///

    // Order state cleared after order is fulfilled or cancelled.
    struct OrderState {
        // Hash of order data used to validate order details stored offchain
        bytes32 orderHash;
        // Account that requested the order
        address requester;
        // Flat fee at time of order request
        uint256 flatFee;
        // Percentage fee rate at time of order request
        uint24 percentageFeeRate;
        // Total amount of received token due to fills
        uint256 received;
        // Total fees paid to treasury
        uint256 feesPaid;
        // Whether a cancellation for this order has been initiated
        bool cancellationInitiated;
    }

    // Order state not cleared after order is fulfilled or cancelled.
    struct OrderInfo {
        // Amount of order token remaining to be used
        uint256 unfilledAmount;
        // Status of order
        OrderStatus status;
    }

    // TODO: do nested structs pack efficiently? If so, use FeeRatesStorage.FeeRates
    struct FeeRatesStorage {
        bool set;
        uint64 perOrderFeeBuy;
        uint24 percentageFeeRateBuy;
        uint64 perOrderFeeSell;
        uint24 percentageFeeRateSell;
    }

    struct FeeRates {
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
    /// @dev blacklist address
    error Blacklist();
    /// @dev Custom error when an order cancellation has already been initiated
    error OrderCancellationInitiated();
    /// @dev Thrown when assetTokenQuantity's precision doesn't match the expected precision in orderDecimals.
    error InvalidPrecision();

    /// @dev Emitted when `treasury` is set
    event TreasurySet(address indexed treasury);
    /// @dev Emitted when `perOrderFee` and `percentageFeeRate` are set
    event FeeSet(uint64 perOrderFee, uint24 percentageFeeRate);
    /// @dev Emitted when orders are paused/unpaused
    event OrdersPaused(bool paused);
    /// @dev Emitted when token lock check contract is set
    event TokenLockCheckSet(ITokenLockCheck indexed tokenLockCheck);
    /// @dev Emitted when fees are set
    event FeesSet(address indexed account, FeeRates feeRates);
    /// @dev Emitted when OrderDecimal is set
    event MaxOrderDecimalsSet(address indexed assetToken, uint256 decimals);

    /// ------------------ Constants ------------------ ///

    /// @dev Used to create EIP-712 compliant hashes as order IDs from order requests and salts
    bytes32 private constant ORDER_TYPE_HASH = keccak256(
        "Order(address recipient,uint256 index,address assetToken,address paymentToken,bool sell,uint8 orderType,uint256 assetTokenQuantity,uint256 paymentTokenQuantity,uint256 price,uint8 tif)"
    );

    /// @notice Operator role for filling and cancelling orders
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @notice Payment token role for whitelisting payment tokens
    bytes32 public constant PAYMENTTOKEN_ROLE = keccak256("PAYMENTTOKEN_ROLE");
    /// @notice Forwarder role for forwarding context awareness
    bytes32 public constant FORWARDER_ROLE = keccak256("FORWARDER_ROLE");
    /// @notice Sell asset role for whitelisting buyable assets
    /// @dev Tokens with decimals > 18 are not supported by current implementation
    bytes32 public constant BUY_ASSET_ROLE = keccak256("BUY_ASSET_ROLE");
    /// @notice Buy asset role for whitelisting sellable assets
    /// @dev Tokens with decimals > 18 are not supported by current implementation
    bytes32 public constant SELL_ASSET_ROLE = keccak256("SELL_ASSET_ROLE");

    /// ------------------ State ------------------ ///

    /// @notice Address to receive fees
    address public treasury;

    /// @notice Transfer restrictor checker
    ITokenLockCheck public tokenLockCheck;

    /// @dev Are orders paused?
    bool public ordersPaused;

    /// @dev Total number of active orders. Onchain enumeration not supported.
    uint256 private _numOpenOrders;

    /// @inheritdoc IOrderProcessor
    mapping(address => uint256) public nextOrderIndex;

    /// @dev Active order state
    mapping(bytes32 => OrderState) private _orders;

    /// @dev Persisted order state
    mapping(bytes32 => OrderInfo) private _orderInfo;

    /// @inheritdoc IOrderProcessor
    mapping(address => mapping(address => uint256)) public escrowedBalanceOf;

    /// @inheritdoc IOrderProcessor
    mapping(address => uint256) public maxOrderDecimals;

    /// @notice Fee schedule for requester
    mapping(address => FeeRatesStorage) private _accountFees;

    /// ------------------ Initialization ------------------ ///

    /// @notice Initialize contract
    /// @param _owner Owner of contract
    /// @param _treasury Address to receive fees
    /// @param defaultFeeRates Default fee rates
    /// @param _tokenLockCheck Token lock check contract
    /// @dev Treasury cannot be zero address
    constructor(address _owner, address _treasury, FeeRates memory defaultFeeRates, ITokenLockCheck _tokenLockCheck)
        AccessControlDefaultAdminRules(0, _owner)
    {
        // Don't send fees to zero address
        if (_treasury == address(0)) revert ZeroAddress();

        // Initialize
        treasury = _treasury;
        _setFees(address(0), defaultFeeRates);
        tokenLockCheck = _tokenLockCheck;
    }

    /// ------------------ Administration ------------------ ///

    /// @dev Check if orders are paused
    modifier whenOrdersNotPaused() {
        if (ordersPaused) revert Paused();
        _;
    }

    /// @notice Set treasury address
    /// @param account Address to receive fees
    /// @dev Only callable by admin
    /// Treasury cannot be zero address
    function setTreasury(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Don't send fees to zero address
        if (account == address(0)) revert ZeroAddress();

        treasury = account;
        emit TreasurySet(account);
    }

    /// @notice Pause/unpause orders
    /// @param pause Pause orders if true, unpause if false
    /// @dev Only callable by admin
    function setOrdersPaused(bool pause) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ordersPaused = pause;
        emit OrdersPaused(pause);
    }

    /// @notice Set token lock check contract
    /// @param _tokenLockCheck Token lock check contract
    /// @dev Only callable by admin
    function setTokenLockCheck(ITokenLockCheck _tokenLockCheck) external onlyRole(DEFAULT_ADMIN_ROLE) {
        tokenLockCheck = _tokenLockCheck;
        emit TokenLockCheckSet(_tokenLockCheck);
    }

    /// @notice Set default fee rates
    /// @param feeRates Fee rates
    /// @dev Only callable by admin
    function setDefaultFees(FeeRates memory feeRates) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFees(address(0), feeRates);
    }

    /// @notice Set unique fee rates for requester
    /// @param requester Requester address
    /// @param feeRates Fee rates
    /// @dev Only callable by admin
    function setFeesForRequester(address requester, FeeRates memory feeRates) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (requester == address(0)) revert ZeroAddress();
        _setFees(requester, feeRates);
    }

    /// @notice Reset fee rates for requester to default
    /// @param requester Requester address
    /// @dev Only callable by admin
    function resetFeesForRequester(address requester) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (requester == address(0)) revert ZeroAddress();
        delete _accountFees[requester];
        FeeRatesStorage memory defaultFeeRates = _accountFees[address(0)];
        emit FeesSet(
            requester,
            FeeRates({
                perOrderFeeBuy: defaultFeeRates.perOrderFeeBuy,
                percentageFeeRateBuy: defaultFeeRates.percentageFeeRateBuy,
                perOrderFeeSell: defaultFeeRates.perOrderFeeSell,
                percentageFeeRateSell: defaultFeeRates.percentageFeeRateSell
            })
        );
    }

    function _setFees(address account, FeeRates memory feeRates) private {
        FeeLib.checkPercentageFeeRate(feeRates.percentageFeeRateBuy);
        FeeLib.checkPercentageFeeRate(feeRates.percentageFeeRateSell);

        _accountFees[account] = FeeRatesStorage({
            set: true,
            perOrderFeeBuy: feeRates.perOrderFeeBuy,
            percentageFeeRateBuy: feeRates.percentageFeeRateBuy,
            perOrderFeeSell: feeRates.perOrderFeeSell,
            percentageFeeRateSell: feeRates.percentageFeeRateSell
        });
        emit FeesSet(account, feeRates);
    }

    /// @notice Set max order decimals for asset token
    /// @param token Asset token
    /// @param decimals Max order decimals
    /// @dev Only callable by admin
    function setMaxOrderDecimals(address token, uint256 decimals) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxOrderDecimals[token] = decimals;
        emit MaxOrderDecimalsSet(token, decimals);
    }

    /// ------------------ Getters ------------------ ///

    /// @inheritdoc IOrderProcessor
    function numOpenOrders() external view returns (uint256) {
        return _numOpenOrders;
    }

    /// @inheritdoc IOrderProcessor
    function getOrderId(address recipient, uint256 index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(recipient, index));
    }

    /// @inheritdoc IOrderProcessor
    function getOrderStatus(bytes32 id) external view returns (OrderStatus) {
        return _orderInfo[id].status;
    }

    /// @inheritdoc IOrderProcessor
    function getUnfilledAmount(bytes32 id) public view returns (uint256) {
        return _orderInfo[id].unfilledAmount;
    }

    /// @inheritdoc IOrderProcessor
    function getTotalReceived(bytes32 id) public view returns (uint256) {
        return _orders[id].received;
    }

    /// @notice Has order cancellation been requested?
    /// @param id Order ID
    function cancelRequested(bytes32 id) external view returns (bool) {
        return _orders[id].cancellationInitiated;
    }

    function _getOrderHash(bytes32 id) internal view returns (bytes32) {
        return _orders[id].orderHash;
    }

    function hasRole(bytes32 role, address account)
        public
        view
        override(AccessControl, IAccessControl, IOrderProcessor)
        returns (bool)
    {
        return super.hasRole(role, account);
    }

    function getAccountFees(address account) external view returns (FeeRates memory) {
        FeeRatesStorage memory feeRates = _accountFees[account];
        // If user does not have a custom fee schedule, use default
        if (!feeRates.set) {
            feeRates = _accountFees[address(0)];
        }
        return FeeRates({
            perOrderFeeBuy: feeRates.perOrderFeeBuy,
            percentageFeeRateBuy: feeRates.percentageFeeRateBuy,
            perOrderFeeSell: feeRates.perOrderFeeSell,
            percentageFeeRateSell: feeRates.percentageFeeRateSell
        });
    }

    /// @inheritdoc IOrderProcessor
    function getFeeRatesForOrder(address requester, bool sell, address token) public view returns (uint256, uint24) {
        FeeRatesStorage memory feeRates = _accountFees[requester];
        // If user does not have a custom fee schedule, use default
        if (!feeRates.set) {
            feeRates = _accountFees[address(0)];
        }
        if (sell) {
            return (FeeLib.flatFeeForOrder(token, feeRates.perOrderFeeSell), feeRates.percentageFeeRateSell);
        } else {
            return (FeeLib.flatFeeForOrder(token, feeRates.perOrderFeeBuy), feeRates.percentageFeeRateBuy);
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

    /// ------------------ Order Lifecycle ------------------ ///

    /// @inheritdoc IOrderProcessor
    function requestOrder(Order calldata order) public whenOrdersNotPaused returns (uint256 index) {
        // cheap checks first
        if (order.recipient == address(0)) revert ZeroAddress();
        uint256 orderAmount = (order.sell) ? order.assetTokenQuantity : order.paymentTokenQuantity;
        // No zero orders
        if (orderAmount == 0) revert ZeroValue();

        // Precision checked for assetTokenQuantity
        uint256 assetPrecision = 10 ** maxOrderDecimals[order.assetToken];
        if (order.assetTokenQuantity % assetPrecision != 0) revert InvalidPrecision();

        // Check for whitelisted tokens
        _checkRole(PAYMENTTOKEN_ROLE, order.paymentToken);
        _checkAssetRole(order.sell, order.assetToken);
        // Check requester
        index = nextOrderIndex[order.recipient];
        bytes32 id = getOrderId(order.recipient, index);
        address requester = getRequester(id);
        if (requester == address(0)) revert ZeroAddress();
        // black list checker
        blackListCheck(order.assetToken, order.paymentToken, order.recipient, requester);

        // Update next order index
        nextOrderIndex[order.recipient] = index + 1;

        // Calculate fees
        (uint256 flatFee, uint24 percentageFeeRate) = getFeeRatesForOrder(requester, order.sell, order.paymentToken);
        uint256 totalFees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, order.paymentTokenQuantity);
        // Check values
        _requestOrderAccounting(id, order, totalFees);

        // Send order to bridge
        emit OrderRequested(order.recipient, index, order);

        // Initialize order state
        _orders[id] = OrderState({
            orderHash: hashOrder(order),
            requester: requester,
            flatFee: flatFee,
            percentageFeeRate: percentageFeeRate,
            received: 0,
            feesPaid: 0,
            cancellationInitiated: false
        });
        _orderInfo[id] = OrderInfo({unfilledAmount: orderAmount, status: OrderStatus.ACTIVE});
        _numOpenOrders++;

        if (order.sell) {
            // update escrowed balance
            escrowedBalanceOf[order.assetToken][order.recipient] += order.assetTokenQuantity;

            // Transfer asset to contract
            IERC20(order.assetToken).safeTransferFrom(msg.sender, address(this), order.assetTokenQuantity);
        } else {
            uint256 quantityIn = order.paymentTokenQuantity + totalFees;
            // update escrowed balance
            escrowedBalanceOf[order.paymentToken][order.recipient] += quantityIn;

            // Escrow payment for purchase
            IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), quantityIn);
        }
    }

    function getRequester(bytes32 id) internal view returns (address) {
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
                order.tif
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
                order.tif
            )
        );
    }

    /// @notice Fill an order
    /// @param order Order to fill
    /// @param index order index
    /// @param fillAmount Amount of order token to fill
    /// @param receivedAmount Amount of received token
    /// @dev Only callable by operator
    function fillOrder(Order calldata order, uint256 index, uint256 fillAmount, uint256 receivedAmount)
        external
        onlyRole(OPERATOR_ROLE)
    {
        // No nonsense
        if (fillAmount == 0) revert ZeroValue();
        if (nextOrderIndex[order.recipient] == 0) revert OrderNotFound();
        bytes32 id = getOrderId(order.recipient, index);
        OrderState memory orderState = _orders[id];
        // Order must exist
        if (orderState.requester == address(0)) revert OrderNotFound();
        // Verify order data
        if (orderState.orderHash != hashOrderCalldata(order)) revert InvalidOrderData();
        // Fill cannot exceed remaining order
        OrderInfo memory orderInfo = _orderInfo[id];
        if (fillAmount > orderInfo.unfilledAmount) revert AmountTooLarge();

        // Calculate earned fees and handle any unique checks
        (uint256 paymentEarned, uint256 feesEarned) =
            _fillOrderAccounting(id, order, orderState, orderInfo.unfilledAmount, fillAmount, receivedAmount);

        // Notify order filled
        emit OrderFill(order.recipient, index, fillAmount, receivedAmount, feesEarned);

        // Update order state
        uint256 unfilledAmount = orderInfo.unfilledAmount - fillAmount;
        _orderInfo[id].unfilledAmount = unfilledAmount;
        // If order is completely filled then clear order state
        if (unfilledAmount == 0) {
            _orderInfo[id].status = OrderStatus.FULFILLED;
            // Notify order fulfilled
            emit OrderFulfilled(order.recipient, index);
            // Clear order state
            delete _orders[id];
            _numOpenOrders--;
        } else {
            // Otherwise update order state
            // Check values
            uint256 estimatedTotalFees =
                FeeLib.estimateTotalFees(orderState.flatFee, orderState.percentageFeeRate, order.paymentTokenQuantity);
            uint256 feesPaid = orderState.feesPaid + feesEarned;
            assert(order.sell || feesPaid <= estimatedTotalFees);
            _orders[id].received = orderState.received + receivedAmount;
            _orders[id].feesPaid = feesPaid;
        }

        // Move tokens
        if (order.sell) {
            // update escrowed balance
            escrowedBalanceOf[order.assetToken][order.recipient] -= fillAmount;
            // Burn the filled quantity from the asset token
            IdShare(order.assetToken).burn(fillAmount);

            // Transfer the received amount from the filler to this contract
            IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), receivedAmount);

            // If there are proceeds from the order, transfer them to the recipient
            if (paymentEarned > 0) {
                IERC20(order.paymentToken).safeTransfer(order.recipient, paymentEarned);
            }
        } else {
            // update escrowed balance
            escrowedBalanceOf[order.paymentToken][order.recipient] -= paymentEarned + feesEarned;
            // Claim payment
            IERC20(order.paymentToken).safeTransfer(msg.sender, paymentEarned);

            // Mint asset
            IdShare(order.assetToken).mint(order.recipient, receivedAmount);
        }

        // If there are fees from the order, transfer them to the treasury
        if (feesEarned > 0) {
            IERC20(order.paymentToken).safeTransfer(treasury, feesEarned);
        }
    }

    function blackListCheck(address assetToken, address paymentToken, address recipient, address sender)
        internal
        view
    {
        if (tokenLockCheck.isTransferLocked(assetToken, recipient)) revert Blacklist();
        if (tokenLockCheck.isTransferLocked(assetToken, sender)) revert Blacklist();
        if (tokenLockCheck.isTransferLocked(paymentToken, recipient)) revert Blacklist();
        if (tokenLockCheck.isTransferLocked(paymentToken, sender)) revert Blacklist();
    }

    /// @dev Check if asset token is whitelisted for buy or sell
    /// @param sell Whether order is sell
    /// @param assetToken Asset token
    function _checkAssetRole(bool sell, address assetToken) internal view {
        if (sell) {
            _checkRole(SELL_ASSET_ROLE, assetToken);
        } else {
            _checkRole(BUY_ASSET_ROLE, assetToken);
        }
    }

    /// @notice Request to cancel an order
    /// @param recipient Recipient of order fills
    /// @param index Order index
    /// @dev Only callable by initial order requester
    /// @dev Emits CancelRequested event to be sent to fulfillment service (operator)
    function requestCancel(address recipient, uint256 index) external {
        bytes32 id = getOrderId(recipient, index);
        if (_orders[id].cancellationInitiated) revert OrderCancellationInitiated();
        // Order must exist
        address requester = _orders[id].requester;
        if (requester == address(0)) revert OrderNotFound();
        // Get cancel requester
        address cancelRequester = getRequester(id);
        // Only requester can request cancellation
        if (requester != cancelRequester) revert NotRequester();

        _orders[id].cancellationInitiated = true;

        // Send cancel request to bridge
        emit CancelRequested(recipient, index);
    }

    /// @notice Cancel an order
    /// @param order Order to cancel
    /// @param index Order index
    /// @param reason Reason for cancellation
    /// @dev Only callable by operator
    function cancelOrder(Order calldata order, uint256 index, string calldata reason)
        external
        onlyRole(OPERATOR_ROLE)
    {
        bytes32 id = getOrderId(order.recipient, index);
        OrderState memory orderState = _orders[id];
        // Order must exist
        if (orderState.requester == address(0)) revert OrderNotFound();
        // Verify order data
        if (orderState.orderHash != hashOrderCalldata(order)) revert InvalidOrderData();

        // Notify order cancelled
        emit OrderCancelled(order.recipient, index, reason);
        // Order is cancelled
        _orderInfo[id].status = OrderStatus.CANCELLED;
        // Clear order state

        delete _orders[id];
        _numOpenOrders--;

        // Calculate refund
        uint256 refund = _cancelOrderAccounting(id, order, orderState, _orderInfo[id].unfilledAmount);

        address refundToken = (order.sell) ? order.assetToken : order.paymentToken;
        // update escrowed balance
        escrowedBalanceOf[refundToken][order.recipient] -= refund;

        // Return escrow
        IERC20(refundToken).safeTransfer(orderState.requester, refund);
    }

    /// ------------------ Virtuals ------------------ ///

    /// @notice Perform any unique order request checks and accounting
    /// @param id Order ID
    /// @param order Order request to process
    /// @param totalFees Total fees for order
    function _requestOrderAccounting(bytes32 id, Order calldata order, uint256 totalFees) internal virtual {}

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
        bytes32 id,
        Order calldata order,
        OrderState memory orderState,
        uint256 unfilledAmount,
        uint256 fillAmount,
        uint256 receivedAmount
    ) internal virtual returns (uint256 paymentEarned, uint256 feesEarned);

    /// @notice Move tokens for order cancellation including fees and escrow
    /// @param id Order ID
    /// @param order Order to cancel
    /// @param orderState Order state
    /// @param unfilledAmount Amount of order token remaining to be used
    /// @return refund Amount of order token to refund to user
    function _cancelOrderAccounting(
        bytes32 id,
        Order calldata order,
        OrderState memory orderState,
        uint256 unfilledAmount
    ) internal virtual returns (uint256 refund);
}
