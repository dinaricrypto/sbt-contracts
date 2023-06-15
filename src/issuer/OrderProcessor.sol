// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {SafeERC20, IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOrderBridge} from "./IOrderBridge.sol";
import {IOrderFees} from "./IOrderFees.sol";

/// @notice Base contract managing orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/issuer/OrderProcessor.sol)
/// Orders are submitted by users and filled by operators
/// Handling of fees is left to the inheriting contract
abstract contract OrderProcessor is
    Initializable,
    UUPSUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable,
    ReentrancyGuardUpgradeable,
    Multicall,
    IOrderBridge
{
    // Handle token permit safely
    using SafeERC20 for IERC20Permit;

    /// ------------------ Types ------------------ ///

    // Specification for an order
    struct OrderRequest {
        // Recipient of order fills
        address recipient;
        // Bridged asset token
        address assetToken;
        // Payment token
        address paymentToken;
        // Amount of incoming order token to be used for fills
        uint256 quantityIn;
    }

    // Order state accounting variables
    struct OrderState {
        // Account that requested the order
        address requester;
        // Amount of order token remaining to be used
        uint256 remainingOrder;
        // Total amount of received token due to fills
        uint256 received;
    }

    // Error messages
    error ZeroAddress();
    error Paused();
    error ZeroValue();
    error NotRequester();
    error OrderNotFound();
    error DuplicateOrder();
    error AmountTooLarge();

    // Events
    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees orderFees);
    event OrdersPaused(bool paused);

    /// ------------------ Immutable ------------------ ///

    /// @dev Used to create EIP-712 compliant hashes as order IDs from order requests and salts
    bytes32 private constant ORDERREQUEST_TYPE_HASH = keccak256(
        "OrderRequest(bytes32 salt,address recipient,address assetToken,address paymentToken,uint256 quantityIn"
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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner, address treasury_, IOrderFees orderFees_) external initializer {
        // Don't send fees to zero address
        if (treasury_ == address(0)) revert ZeroAddress();

        // Initialize super contracts
        __UUPSUpgradeable_init_unchained();
        __AccessControlDefaultAdminRules_init_unchained(0, owner);
        __ReentrancyGuard_init_unchained();

        // Initialize treasury and order fees
        treasury = treasury_;
        orderFees = orderFees_;

        // Grant admin role to owner
        _grantRole(ADMIN_ROLE, owner);
    }

    // Restrict upgrades to owner
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// ------------------ Administration ------------------ ///

    modifier whenOrdersNotPaused() {
        if (ordersPaused) revert Paused();
        _;
    }

    /// @notice Set treasury address
    /// @param account Address to receive fees
    /// @dev Only callable by admin
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

    /// @notice Get order ID deterministically from order request and salt
    /// @param orderRequest Order request to get ID for
    /// @param salt Salt used to generate unique order ID
    /// @dev Compliant with EIP-712 for convenient offchain computation
    function getOrderIdFromOrderRequest(OrderRequest memory orderRequest, bytes32 salt) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDERREQUEST_TYPE_HASH,
                salt,
                orderRequest.recipient,
                orderRequest.assetToken,
                orderRequest.paymentToken,
                orderRequest.quantityIn
            )
        );
    }

    /// @inheritdoc IOrderBridge
    function getOrderId(Order calldata order, bytes32 salt) external pure returns (bytes32) {
        return getOrderIdFromOrderRequest(getOrderRequestForOrder(order), salt);
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
    /// @param orderRequest Order request to submit
    /// @param salt Salt used to generate unique order ID
    function requestOrder(OrderRequest calldata orderRequest, bytes32 salt) public nonReentrant whenOrdersNotPaused {
        _validateRequest(orderRequest);
        bytes32 orderId = getOrderIdFromOrderRequest(orderRequest, salt);
        // Order must not already exist
        if (_orders[orderId].remainingOrder > 0) revert DuplicateOrder();

        // Get order from request and move tokens
        Order memory order = _requestOrderAccounting(orderRequest, orderId);

        // Initialize accounting
        _createOrder(order, salt, orderId);
    }

    /// @notice Request an order with token permit
    /// @param orderRequest Order request to submit
    /// @param salt Salt used to generate unique order ID
    /// @param permitToken Token to permit
    /// @param value Amount of token to permit
    /// @param deadline Expiration for permit
    /// @param v Signature v
    /// @param r Signature r
    /// @param s Signature s
    // slither-disable-next-line reentrancy-no-eth,reentrancy-benign
    function requestOrderWithPermit(
        OrderRequest calldata orderRequest,
        bytes32 salt,
        address permitToken,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenOrdersNotPaused {
        _validateRequest(orderRequest);
        bytes32 orderId = getOrderIdFromOrderRequest(orderRequest, salt);
        // Order must not already exist
        if (_orders[orderId].remainingOrder > 0) revert DuplicateOrder();

        // Approve incoming tokens
        IERC20Permit(permitToken).safePermit(msg.sender, address(this), value, deadline, v, r, s);
        // Get order from request and move tokens
        Order memory order = _requestOrderAccounting(orderRequest, orderId);

        // Initialize accounting
        _createOrder(order, salt, orderId);
    }

    /// @dev Basic validity check on order request
    function _validateRequest(OrderRequest calldata orderRequest) private view {
        // Reject spam orders
        if (orderRequest.quantityIn == 0) revert ZeroValue();
        // Check for whitelisted tokens
        _checkRole(ASSETTOKEN_ROLE, orderRequest.assetToken);
        _checkRole(PAYMENTTOKEN_ROLE, orderRequest.paymentToken);
    }

    /// @dev Send order to bridge and initialize accounting
    function _createOrder(Order memory order, bytes32 salt, bytes32 orderId) private {
        // Send order to bridge
        emit OrderRequested(orderId, order.recipient, order, salt);

        // Initialize order state
        uint256 orderAmount = order.sell ? order.assetTokenQuantity : order.paymentTokenQuantity;
        _orders[orderId] = OrderState({requester: msg.sender, remainingOrder: orderAmount, received: 0});
        _numOpenOrders++;
    }

    /// @notice Fill an order
    /// @param orderRequest Order request to fill
    /// @param salt Salt used to generate unique order ID
    /// @param fillAmount Amount of order token to fill
    /// @param receivedAmount Amount of received token
    /// @dev Only callable by operator
    function fillOrder(OrderRequest calldata orderRequest, bytes32 salt, uint256 fillAmount, uint256 receivedAmount)
        external
        nonReentrant
        onlyRole(OPERATOR_ROLE)
    {
        // No nonsense
        if (fillAmount == 0) revert ZeroValue();
        bytes32 orderId = getOrderIdFromOrderRequest(orderRequest, salt);
        OrderState memory orderState = _orders[orderId];
        // Order must exist
        if (orderState.requester == address(0)) revert OrderNotFound();
        // Fill cannot exceed remaining order
        if (fillAmount > orderState.remainingOrder) revert AmountTooLarge();

        // Notify order filled
        emit OrderFill(orderId, orderRequest.recipient, fillAmount, receivedAmount);

        // Update order state
        uint256 remainingOrder = orderState.remainingOrder - fillAmount;
        if (remainingOrder == 0) {
            emit OrderFulfilled(orderId, orderRequest.recipient);
            delete _orders[orderId];
            _numOpenOrders--;
        } else {
            _orders[orderId].remainingOrder = remainingOrder;
            _orders[orderId].received = orderState.received + receivedAmount;
        }

        // Move tokens
        _fillOrderAccounting(orderRequest, orderId, orderState, fillAmount, receivedAmount, fillAmount);
    }

    /// @notice Request to cancel an order
    /// @param orderRequest Order request to cancel
    /// @param salt Salt used to generate unique order ID
    /// @dev Only callable by order requester
    function requestCancel(OrderRequest calldata orderRequest, bytes32 salt) external {
        bytes32 orderId = getOrderIdFromOrderRequest(orderRequest, salt);
        address requester = _orders[orderId].requester;
        // Order must exist
        if (requester == address(0)) revert OrderNotFound();
        // Only requester can cancel
        if (requester != msg.sender) revert NotRequester();

        // Send cancel request to bridge
        emit CancelRequested(orderId, orderRequest.recipient);
    }

    /// @notice Cancel an order
    /// @param orderRequest Order request to cancel
    /// @param salt Salt used to generate unique order ID
    /// @param reason Reason for cancellation
    /// @dev Only callable by operator
    function cancelOrder(OrderRequest calldata orderRequest, bytes32 salt, string calldata reason)
        external
        nonReentrant
        onlyRole(OPERATOR_ROLE)
    {
        bytes32 orderId = getOrderIdFromOrderRequest(orderRequest, salt);
        OrderState memory orderState = _orders[orderId];
        // Order must exist
        if (orderState.requester == address(0)) revert OrderNotFound();

        // Notify order cancelled
        emit OrderCancelled(orderId, orderRequest.recipient, reason);

        // Clear order state
        delete _orders[orderId];
        _numOpenOrders--;

        // Move tokens
        _cancelOrderAccounting(orderRequest, orderId, orderState);
    }

    /// ------------------ Virtuals ------------------ ///

    /// @notice Get corresponding OrderRequest for an Order
    /// @dev Declared pure to be calculable for hypothetical orders
    function getOrderRequestForOrder(Order calldata order) public pure virtual returns (OrderRequest memory);

    /// @notice Compile order from request and move tokens including fees, escrow, and amount to fill
    /// @param orderRequest Order request to process
    /// @param orderId Order ID
    /// @return order Order to send to bridge
    /// @dev Result used to initialize order accounting
    function _requestOrderAccounting(OrderRequest calldata orderRequest, bytes32 orderId)
        internal
        virtual
        returns (Order memory order);

    /// @notice Move tokens for order fill including fees and escrow
    /// @param orderRequest Order request to fill
    /// @param orderId Order ID
    /// @param orderState Order state
    /// @param fillAmount Amount of order token filled
    /// @param receivedAmount Amount of received token
    /// @param claimPaymentAmount Amount of payment token to claim
    function _fillOrderAccounting(
        OrderRequest calldata orderRequest,
        bytes32 orderId,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount,
        // TODO: remove claimpayment amount - only used for certain buy processors
        uint256 claimPaymentAmount
    ) internal virtual;

    /// @notice Move tokens for order cancellation including fees and escrow
    /// @param orderRequest Order request to cancel
    /// @param orderId Order ID
    /// @param orderState Order state
    function _cancelOrderAccounting(OrderRequest calldata orderRequest, bytes32 orderId, OrderState memory orderState)
        internal
        virtual;
}
