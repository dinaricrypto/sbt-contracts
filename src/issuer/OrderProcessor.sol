// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {AccessControlDefaultAdminRules} from
    "openzeppelin-contracts/contracts/access/AccessControlDefaultAdminRules.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {SelfPermit} from "../common/SelfPermit.sol";
import {IOrderBridge} from "./IOrderBridge.sol";
import {IOrderFees} from "./IOrderFees.sol";

/// @notice Base contract managing orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/issuer/OrderProcessor.sol)
/// Orders are submitted by users and filled by operators
/// Handling of fees is left to the inheriting contract
/// Each inheritor can craft a unique order processing flow
/// It is recommended that implementations offer a single process for all orders
///   This maintains clarity for users and for interpreting contract token balances
/// Specifies a generic order request struct such that
///   inheriting contracts must implement unique request methods to handle multiple order processes simultaneously
/// TODO: Design - Fee contract required and specified here, but not used. Should fee contract be specified in inheritor?
///   or should fee handling primitives be specified here?
/// Order lifecycle (fulfillment):
///   1. User requests an order (requestOrder)
///   2. [Optional] Operator partially fills the order (fillOrder)
///   3. Operator completely fulfills the order (fillOrder)
/// Order lifecycle (cancellation):
///   1. User requests an order (requestOrder)
///   2. [Optional] Operator partially fills the order (fillOrder)
///   3. [Optional] User requests cancellation (requestCancel)
///   4. Operator cancels the order (cancelOrder)
abstract contract OrderProcessor is
    AccessControlDefaultAdminRules,
    Multicall,
    SelfPermit,
    IOrderBridge
{
    /// ------------------ Types ------------------ ///

    // Order state accounting variables
    struct OrderState {
        // Account that requested the order
        address requester;
        // Amount of order token remaining to be used
        uint256 remainingOrder;
        // Total amount of received token due to fills
        uint256 received;
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
    /// @dev Order already exists
    error DuplicateOrder();
    /// @dev Amount too large
    error AmountTooLarge();
    /// @dev Order type mismatch
    error OrderTypeMismatch();

    /// @dev Emitted when `treasury` is set
    event TreasurySet(address indexed treasury);
    /// @dev Emitted when `orderFees` is set
    event OrderFeesSet(IOrderFees indexed orderFees);
    /// @dev Emitted when orders are paused/unpaused
    event OrdersPaused(bool paused);

    /// ------------------ Constants ------------------ ///

    /// @dev Used to create EIP-712 compliant hashes as order IDs from order requests and salts
    bytes32 private constant ORDER_TYPE_HASH = keccak256(
        "Order(bytes32 salt,address recipient,address assetToken,address paymentToken,bool sell,uint8 orderType,uint256 assetTokenQuantity,uint256 paymentTokenQuantity,uint256 price,uint8 tif)"
    );

    /// @notice Admin role for managing treasury, fees, and paused state
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Operator role for filling and cancelling orders
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @notice Payment token role for whitelisting payment tokens
    bytes32 public constant PAYMENTTOKEN_ROLE = keccak256("PAYMENTTOKEN_ROLE");
    /// @notice Asset token role for whitelisting asset tokens
    /// @dev Tokens with decimals > 18 are not supported by current OrderFees implementation
    bytes32 public constant ASSETTOKEN_ROLE = keccak256("ASSETTOKEN_ROLE");

    /// ------------------ State ------------------ ///

    /// @notice Address to receive fees
    address public treasury;

    /// @notice Fee specification contract
    IOrderFees public orderFees;

    /// @dev Are orders paused?
    bool public ordersPaused;

    /// @dev Total number of active orders. Onchain enumeration not supported.
    uint256 private _numOpenOrders;

    /// @dev Active orders
    mapping(bytes32 => OrderState) private _orders;

    /// ------------------ Initialization ------------------ ///

    /// @notice Initialize contract
    /// @param _owner Owner of contract
    /// @param treasury_ Address to receive fees
    /// @param orderFees_ Fee specification contract
    /// @dev Treasury cannot be zero address
    constructor(address _owner, address treasury_, IOrderFees orderFees_)
        AccessControlDefaultAdminRules(0, _owner)
    {
        // Don't send fees to zero address
        if (treasury_ == address(0)) revert ZeroAddress();

        // Initialize treasury and order fees
        treasury = treasury_;
        orderFees = orderFees_;

        // Grant admin role to owner
        _grantRole(ADMIN_ROLE, _owner);
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
    function setTreasury(address account) external onlyRole(ADMIN_ROLE) {
        // Don't send fees to zero address
        if (account == address(0)) revert ZeroAddress();

        treasury = account;
        emit TreasurySet(account);
    }

    /// @notice Set order fees contract
    /// @param fees Order fees contract
    /// @dev Only callable by admin
    function setOrderFees(IOrderFees fees) external onlyRole(ADMIN_ROLE) {
        orderFees = fees;
        emit OrderFeesSet(fees);
    }

    /// @notice Pause/unpause orders
    /// @param pause Pause orders if true, unpause if false
    /// @dev Only callable by admin
    function setOrdersPaused(bool pause) external onlyRole(ADMIN_ROLE) {
        ordersPaused = pause;
        emit OrdersPaused(pause);
    }

    /// ------------------ Getters ------------------ ///

    /// @inheritdoc IOrderBridge
    function numOpenOrders() external view returns (uint256) {
        return _numOpenOrders;
    }

    /// @inheritdoc IOrderBridge
    function getOrderId(Order memory order, bytes32 salt) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPE_HASH,
                salt,
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

    /// @inheritdoc IOrderBridge
    function isOrderActive(bytes32 id) public view returns (bool) {
        return _orders[id].remainingOrder > 0;
    }

    /// @inheritdoc IOrderBridge
    function getRemainingOrder(bytes32 id) public view returns (uint256) {
        return _orders[id].remainingOrder;
    }

    /// @inheritdoc IOrderBridge
    function getTotalReceived(bytes32 id) public view returns (uint256) {
        return _orders[id].received;
    }

    /// ------------------ Order Lifecycle ------------------ ///

    /// @notice Request an order
    /// @param order Order  to submit
    /// @param salt Salt used to generate unique order ID
    /// @dev Emits OrderRequested event to be sent to fulfillment service (operator)
    function requestOrder(Order calldata order, bytes32 salt) public whenOrdersNotPaused {
        uint256 orderAmount = order.sell ? order.assetTokenQuantity : order.paymentTokenQuantity;
        // No zero orders
        if (orderAmount == 0) revert ZeroValue();
        // Check for whitelisted tokens
        _checkRole(ASSETTOKEN_ROLE, order.assetToken);
        _checkRole(PAYMENTTOKEN_ROLE, order.paymentToken);
        bytes32 orderId = getOrderId(order, salt);
        // Order must not already exist
        if (_orders[orderId].remainingOrder > 0) revert DuplicateOrder();

        // Send order to bridge
        emit OrderRequested(orderId, order.recipient, order, salt);

        // Initialize order state
        _orders[orderId] = OrderState({requester: msg.sender, remainingOrder: orderAmount, received: 0});
        _numOpenOrders++;

        // Move tokens
        _requestOrderAccounting(order, orderId);
    }

    /// @notice Fill an order
    /// @param order Order  to fill
    /// @param salt Salt used to generate unique order ID
    /// @param fillAmount Amount of order token to fill
    /// @param receivedAmount Amount of received token
    /// @dev Only callable by operator
    function fillOrder(Order calldata order, bytes32 salt, uint256 fillAmount, uint256 receivedAmount)
        external
        onlyRole(OPERATOR_ROLE)
    {
        // No nonsense
        if (fillAmount == 0) revert ZeroValue();
        bytes32 orderId = getOrderId(order, salt);
        OrderState memory orderState = _orders[orderId];
        // Order must exist
        if (orderState.requester == address(0)) revert OrderNotFound();
        // Fill cannot exceed remaining order
        if (fillAmount > orderState.remainingOrder) revert AmountTooLarge();

        // Notify order filled
        emit OrderFill(orderId, order.recipient, fillAmount, receivedAmount);

        // Update order state
        uint256 remainingOrder = orderState.remainingOrder - fillAmount;
        // If order is completely filled then clear order state
        if (remainingOrder == 0) {
            // Notify order fulfilled
            emit OrderFulfilled(orderId, order.recipient);
            // Clear order state
            delete _orders[orderId];
            _numOpenOrders--;
        } else {
            // Otherwise update order state
            _orders[orderId].remainingOrder = remainingOrder;
            _orders[orderId].received = orderState.received + receivedAmount;
        }

        // Move tokens
        _fillOrderAccounting(order, orderId, orderState, fillAmount, receivedAmount);
    }

    /// @notice Request to cancel an order
    /// @param order Order  to cancel
    /// @param salt Salt used to generate unique order ID
    /// @dev Only callable by initial order requester
    /// @dev Emits CancelRequested event to be sent to fulfillment service (operator)
    function requestCancel(Order calldata order, bytes32 salt) external {
        bytes32 orderId = getOrderId(order, salt);
        address requester = _orders[orderId].requester;
        // Order must exist
        if (requester == address(0)) revert OrderNotFound();
        // Only requester can request cancellation
        if (requester != msg.sender) revert NotRequester();

        // Send cancel request to bridge
        emit CancelRequested(orderId, order.recipient);
    }

    /// @notice Cancel an order
    /// @param order Order  to cancel
    /// @param salt Salt used to generate unique order ID
    /// @param reason Reason for cancellation
    /// @dev Only callable by operator
    function cancelOrder(Order calldata order, bytes32 salt, string calldata reason)
        external
        onlyRole(OPERATOR_ROLE)
    {
        bytes32 orderId = getOrderId(order, salt);
        OrderState memory orderState = _orders[orderId];
        // Order must exist
        if (orderState.requester == address(0)) revert OrderNotFound();

        // Notify order cancelled
        emit OrderCancelled(orderId, order.recipient, reason);

        // Clear order state
        delete _orders[orderId];
        _numOpenOrders--;

        // Move tokens
        _cancelOrderAccounting(order, orderId, orderState);
    }

    /// ------------------ Virtuals ------------------ ///

    /// @notice Compile order from request and move tokens including fees, escrow, and amount to fill
    /// @param order Order  to process
    /// @param orderId Order ID
    /// @dev Result used to initialize order accounting
    function _requestOrderAccounting(Order calldata order, bytes32 orderId) internal virtual;

    /// @notice Move tokens for order fill including fees and escrow
    /// @param order Order  to fill
    /// @param orderId Order ID
    /// @param orderState Order state
    /// @param fillAmount Amount of order token filled
    /// @param receivedAmount Amount of received token
    function _fillOrderAccounting(
        Order calldata order,
        bytes32 orderId,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount
    ) internal virtual;

    /// @notice Move tokens for order cancellation including fees and escrow
    /// @param order Order  to cancel
    /// @param orderId Order ID
    /// @param orderState Order state
    function _cancelOrderAccounting(Order calldata order, bytes32 orderId, OrderState memory orderState)
        internal
        virtual;
}
