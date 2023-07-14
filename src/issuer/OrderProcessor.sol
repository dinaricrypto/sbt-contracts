// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
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
    Initializable,
    UUPSUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable,
    ReentrancyGuardUpgradeable,
    Multicall,
    SelfPermit,
    IOrderBridge
{
    /// ------------------ Types ------------------ ///

    // Order request format
    struct OrderRequest {
        // Recipient of order fills
        address recipient;
        // Bridged asset token
        address assetToken;
        // Payment token
        address paymentToken;
        // Amount of incoming order token to be used for fills
        uint256 quantityIn;
        // price enquiry for the request
        uint256 price;
    }

    // Order state accounting variables
    struct OrderState {
        // Hash of order data used to validate order details stored offchain
        bytes32 orderHash;
        // Account that requested the order
        address requester;
        // Amount of order token remaining to be used
        uint256 remainingOrder;
        // Total amount of received token due to fills
        uint256 received;
    }

    // Order execution specification
    struct OrderConfig {
        // Buy or sell
        bool sell;
        // Market or limit
        OrderType orderType;
        // Amount of asset token to be used for fills
        uint256 assetTokenQuantity;
        // Amount of payment token to be used for fills
        uint256 paymentTokenQuantity;
        // Price for limit orders
        uint256 price;
        // Time in force
        TIF tif;
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
    /// @dev Amount too large
    error AmountTooLarge();

    /// @dev Emitted when `treasury` is set
    event TreasurySet(address indexed treasury);
    /// @dev Emitted when `orderFees` is set
    event OrderFeesSet(IOrderFees indexed orderFees);
    /// @dev Emitted when orders are paused/unpaused
    event OrdersPaused(bool paused);

    /// ------------------ Constants ------------------ ///

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

    /// @dev Next order index to use for onchain enumeration of orders per recipient
    mapping(address => uint256) private _nextOrderIndex;

    /// @dev Active orders
    mapping(bytes32 => OrderState) private _orders;

    /// ------------------ Initialization ------------------ ///

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize contract
    /// @param owner Owner of contract
    /// @param treasury_ Address to receive fees
    /// @param orderFees_ Fee specification contract
    /// @dev Treasury cannot be zero address
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
    function getOrderId(address recipient, uint256 index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(recipient, index));
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
    /// @dev Emits OrderRequested event to be sent to fulfillment service (operator)
    function requestOrder(OrderRequest calldata orderRequest)
        public
        nonReentrant
        whenOrdersNotPaused
        returns (uint256 index)
    {
        // Reject spam orders
        if (orderRequest.quantityIn == 0) revert ZeroValue();
        // Check for whitelisted tokens
        _checkRole(ASSETTOKEN_ROLE, orderRequest.assetToken);
        _checkRole(PAYMENTTOKEN_ROLE, orderRequest.paymentToken);

        index = _nextOrderIndex[orderRequest.recipient]++;
        bytes32 id = getOrderId(orderRequest.recipient, index);

        // Get order from request and move tokens
        OrderConfig memory orderConfig = _requestOrderAccounting(id, orderRequest);
        Order memory order = Order({
            recipient: orderRequest.recipient,
            index: index,
            quantityIn: orderRequest.quantityIn,
            assetToken: orderRequest.assetToken,
            paymentToken: orderRequest.paymentToken,
            sell: orderConfig.sell,
            orderType: orderConfig.orderType,
            assetTokenQuantity: orderConfig.assetTokenQuantity,
            paymentTokenQuantity: orderConfig.paymentTokenQuantity,
            price: orderConfig.price,
            tif: orderConfig.tif
        });

        // Send order to bridge
        emit OrderRequested(order.recipient, index, order);

        // Initialize order state
        uint256 orderAmount = order.sell ? order.assetTokenQuantity : order.paymentTokenQuantity;
        _orders[id] =
            OrderState({orderHash: hashOrder(order), requester: msg.sender, remainingOrder: orderAmount, received: 0});
        _numOpenOrders++;
    }

    /// @notice Hash order data for validation
    function hashOrder(Order memory order) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                order.recipient,
                order.index,
                order.quantityIn,
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
    /// @param fillAmount Amount of order token to fill
    /// @param receivedAmount Amount of received token
    /// @dev Only callable by operator
    function fillOrder(Order calldata order, uint256 fillAmount, uint256 receivedAmount)
        external
        nonReentrant
        onlyRole(OPERATOR_ROLE)
    {
        // No nonsense
        if (fillAmount == 0) revert ZeroValue();
        bytes32 id = getOrderId(order.recipient, order.index);
        OrderState memory orderState = _orders[id];
        // Order must exist
        if (orderState.requester == address(0)) revert OrderNotFound();
        // Fill cannot exceed remaining order
        if (fillAmount > orderState.remainingOrder) revert AmountTooLarge();

        // Notify order filled
        emit OrderFill(order.recipient, order.index, fillAmount, receivedAmount);

        // Update order state
        uint256 remainingOrder = orderState.remainingOrder - fillAmount;
        // If order is completely filled then clear order state
        if (remainingOrder == 0) {
            // Notify order fulfilled
            emit OrderFulfilled(order.recipient, order.index);
            // Clear order state
            delete _orders[id];
            _numOpenOrders--;
        } else {
            // Otherwise update order state
            _orders[id].remainingOrder = remainingOrder;
            _orders[id].received = orderState.received + receivedAmount;
        }

        // Move tokens
        _fillOrderAccounting(id, order, orderState, fillAmount, receivedAmount);
    }

    /// @notice Request to cancel an order
    /// @param recipient Recipient of order fills
    /// @param index Order index
    /// @dev Only callable by initial order requester
    /// @dev Emits CancelRequested event to be sent to fulfillment service (operator)
    function requestCancel(address recipient, uint256 index) external {
        bytes32 id = getOrderId(recipient, index);
        address requester = _orders[id].requester;
        // Order must exist
        if (requester == address(0)) revert OrderNotFound();
        // Only requester can request cancellation
        if (requester != msg.sender) revert NotRequester();

        // Send cancel request to bridge
        emit CancelRequested(recipient, index);
    }

    /// @notice Cancel an order
    /// @param order Order to cancel
    /// @param reason Reason for cancellation
    /// @dev Only callable by operator
    function cancelOrder(Order calldata order, string calldata reason) external nonReentrant onlyRole(OPERATOR_ROLE) {
        bytes32 id = getOrderId(order.recipient, order.index);
        OrderState memory orderState = _orders[id];
        // Order must exist
        if (orderState.requester == address(0)) revert OrderNotFound();

        // Notify order cancelled
        emit OrderCancelled(order.recipient, order.index, reason);

        // Clear order state
        delete _orders[id];
        _numOpenOrders--;

        // Move tokens
        _cancelOrderAccounting(id, order, orderState);
    }

    /// ------------------ Virtuals ------------------ ///

    /// @notice Compile order from request and move tokens including fees, escrow, and amount to fill
    /// @param id Order ID
    /// @param orderRequest Order request to process
    /// @return orderConfig Order execution specification
    /// @dev Result used to initialize order accounting
    function _requestOrderAccounting(bytes32 id, OrderRequest calldata orderRequest)
        internal
        virtual
        returns (OrderConfig memory orderConfig);

    /// @notice Move tokens for order fill including fees and escrow
    /// @param id Order ID
    /// @param order Order to fill
    /// @param orderState Order state
    /// @param fillAmount Amount of order token filled
    /// @param receivedAmount Amount of received token
    function _fillOrderAccounting(
        bytes32 id,
        Order calldata order,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount
    ) internal virtual;

    /// @notice Move tokens for order cancellation including fees and escrow
    /// @param id Order ID
    /// @param order Order to cancel
    /// @param orderState Order state
    function _cancelOrderAccounting(bytes32 id, Order calldata order, OrderState memory orderState) internal virtual;
}
