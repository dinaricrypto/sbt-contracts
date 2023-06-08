// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {SafeERC20, IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IOrderBridge.sol";
import "./IOrderFees.sol";

/// @notice Base contract managing orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/issuer/OrderProcessor.sol)
abstract contract OrderProcessor is
    Initializable,
    UUPSUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable,
    ReentrancyGuardUpgradeable,
    Multicall,
    IOrderBridge
{
    using SafeERC20 for IERC20Permit;

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

    error ZeroAddress();
    error Paused();
    error ZeroValue();
    error NotRequester();
    error OrderNotFound();
    error DuplicateOrder();
    error AmountTooLarge();

    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees orderFees);
    event OrdersPaused(bool paused);

    bytes32 private constant ORDERREQUEST_TYPE_HASH = keccak256(
        "OrderRequest(bytes32 salt,address recipient,address assetToken,address paymentToken,uint256 quantityIn"
    );

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAYMENTTOKEN_ROLE = keccak256("PAYMENTTOKEN_ROLE");
    /// @dev Tokens with decimals > 18 are not supported by current OrderFees implementation
    bytes32 public constant ASSETTOKEN_ROLE = keccak256("ASSETTOKEN_ROLE");

    /// @dev Address to receive fees
    address public treasury;

    /// @dev Fee specification contract
    IOrderFees public orderFees;

    /// @dev Are orders paused?
    bool public ordersPaused;

    uint256 private _numOpenOrders;

    /// @dev Active orders
    mapping(bytes32 => OrderState) private _orders;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner, address treasury_, IOrderFees orderFees_) external initializer {
        __AccessControlDefaultAdminRules_init_unchained(0, owner);
        _grantRole(ADMIN_ROLE, owner);

        if (treasury_ == address(0)) revert ZeroAddress();

        treasury = treasury_;
        orderFees = orderFees_;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}

    modifier whenOrdersNotPaused() {
        if (ordersPaused) revert Paused();
        _;
    }

    function setTreasury(address account) external onlyRole(ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddress();

        treasury = account;
        emit TreasurySet(account);
    }

    function setOrderFees(IOrderFees fees) external onlyRole(ADMIN_ROLE) {
        orderFees = fees;
        emit OrderFeesSet(fees);
    }

    function setOrdersPaused(bool pause) external onlyRole(ADMIN_ROLE) {
        ordersPaused = pause;
        emit OrdersPaused(pause);
    }

    /// @inheritdoc IOrderBridge
    function numOpenOrders() external view returns (uint256) {
        return _numOpenOrders;
    }

    /// @notice Get order ID deterministically from order request and salt
    /// @param orderRequest Order request to get ID for
    /// @param salt Salt used to generate unique order ID
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

    /// @notice Get total received for order
    /// @param id Order ID to check
    function getTotalReceived(bytes32 id) public view returns (uint256) {
        return _orders[id].received;
    }

    /// @notice Get corresponding OrderRequest for an Order
    function getOrderRequestForOrder(Order calldata order) public pure virtual returns (OrderRequest memory);

    /// @notice Request an order
    /// @param orderRequest Order request to submit
    /// @param salt Salt used to generate unique order ID
    function requestOrder(OrderRequest calldata orderRequest, bytes32 salt) public nonReentrant whenOrdersNotPaused {
        _validateRequest(orderRequest);
        bytes32 orderId = getOrderIdFromOrderRequest(orderRequest, salt);
        if (_orders[orderId].remainingOrder > 0) revert DuplicateOrder();

        Order memory order = _requestOrderAccounting(orderRequest, orderId);

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
        if (_orders[orderId].remainingOrder > 0) revert DuplicateOrder();

        IERC20Permit(permitToken).safePermit(msg.sender, address(this), value, deadline, v, r, s);
        Order memory order = _requestOrderAccounting(orderRequest, orderId);

        _createOrder(order, salt, orderId);
    }

    function _validateRequest(OrderRequest calldata orderRequest) private view {
        // if (msg.sender == address(0)) revert ZeroAddress();
        if (orderRequest.quantityIn == 0) revert ZeroValue();
        _checkRole(ASSETTOKEN_ROLE, orderRequest.assetToken);
        _checkRole(PAYMENTTOKEN_ROLE, orderRequest.paymentToken);
    }

    function _createOrder(Order memory order, bytes32 salt, bytes32 orderId) private {
        emit OrderRequested(orderId, order.recipient, order, salt);

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
        if (fillAmount == 0) revert ZeroValue();
        bytes32 orderId = getOrderIdFromOrderRequest(orderRequest, salt);
        OrderState memory orderState = _orders[orderId];
        if (orderState.requester == address(0)) revert OrderNotFound();
        if (fillAmount > orderState.remainingOrder) revert AmountTooLarge();

        emit OrderFill(orderId, orderRequest.recipient, fillAmount, receivedAmount);
        uint256 remainingOrder = orderState.remainingOrder - fillAmount;
        if (remainingOrder == 0) {
            emit OrderFulfilled(orderId, orderRequest.recipient);
            delete _orders[orderId];
            _numOpenOrders--;
        } else {
            _orders[orderId].remainingOrder = remainingOrder;
            _orders[orderId].received = orderState.received + receivedAmount;
        }

        _fillOrderAccounting(orderRequest, orderId, orderState, fillAmount, receivedAmount, fillAmount);
    }

    /// @notice Request to cancel an order
    /// @param orderRequest Order request to cancel
    /// @param salt Salt used to generate unique order ID
    /// @dev Only callable by order requester
    function requestCancel(OrderRequest calldata orderRequest, bytes32 salt) external {
        bytes32 orderId = getOrderIdFromOrderRequest(orderRequest, salt);
        address requester = _orders[orderId].requester;
        if (requester == address(0)) revert OrderNotFound();
        if (requester != msg.sender) revert NotRequester();

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
        if (orderState.requester == address(0)) revert OrderNotFound();

        emit OrderCancelled(orderId, orderRequest.recipient, reason);
        delete _orders[orderId];
        _numOpenOrders--;

        _cancelOrderAccounting(orderRequest, orderId, orderState);
    }

    /// @notice Process an order request including fees, escrow, and calculating order amount to fill
    /// @param orderRequest Order request to process
    /// @param orderId Order ID
    /// @return order Order to send to bridge
    function _requestOrderAccounting(OrderRequest calldata orderRequest, bytes32 orderId)
        internal
        virtual
        returns (Order memory order);

    /// @notice Process an order fill including fees and escrow
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

    /// @notice Process an order cancellation including fees and escrow
    /// @param orderRequest Order request to cancel
    /// @param orderId Order ID
    /// @param orderState Order state
    function _cancelOrderAccounting(OrderRequest calldata orderRequest, bytes32 orderId, OrderState memory orderState)
        internal
        virtual;
}
