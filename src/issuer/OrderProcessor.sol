// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/AccessControlDefaultAdminRulesUpgradeable.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {SafeERC20, IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IOrderBridge.sol";
import "./IOrderFees.sol";

/// @notice Base contract managing orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/issuer/Issuer.sol)
abstract contract OrderProcessor is
    Initializable,
    UUPSUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable,
    Multicall,
    IOrderBridge
{
    using SafeERC20 for IERC20Permit;

    struct OrderRequest {
        address recipient;
        address assetToken;
        address paymentToken;
        uint256 quantityIn;
    }

    struct OrderState {
        uint256 remainingOrder;
        uint256 received;
    }

    error ZeroAddress();
    error Paused();
    error ZeroValue();
    error NotRecipient();
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
    bytes32 public constant ASSETTOKEN_ROLE = keccak256("ASSETTOKEN_ROLE");

    address public treasury;

    IOrderFees public orderFees;

    uint256 public numOpenOrders;

    bool public ordersPaused;

    /// @dev active orders
    mapping(bytes32 => OrderState) internal _orders;

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

    function getOrderIdFromOrderRequest(OrderRequest memory order, bytes32 salt) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDERREQUEST_TYPE_HASH, salt, order.recipient, order.assetToken, order.paymentToken, order.quantityIn
            )
        );
    }

    function getOrderId(Order calldata order, bytes32 salt) external pure returns (bytes32) {
        return getOrderIdFromOrderRequest(getOrderRequestForOrder(order), salt);
    }

    function isOrderActive(bytes32 id) external view returns (bool) {
        return _orders[id].remainingOrder > 0;
    }

    function getRemainingOrder(bytes32 id) external view returns (uint256) {
        return _orders[id].remainingOrder;
    }

    function getTotalReceived(bytes32 id) external view returns (uint256) {
        return _orders[id].received;
    }

    function getOrderRequestForOrder(Order calldata order) public pure virtual returns (OrderRequest memory);

    // TODO: generic totalQuantityForOrder

    function requestOrder(OrderRequest calldata order, bytes32 salt) public whenOrdersNotPaused {
        if (order.quantityIn == 0) revert ZeroValue();
        _checkRole(ASSETTOKEN_ROLE, order.assetToken);
        _checkRole(PAYMENTTOKEN_ROLE, order.paymentToken);
        bytes32 orderId = getOrderIdFromOrderRequest(order, salt);
        if (_orders[orderId].remainingOrder > 0) revert DuplicateOrder();

        _requestOrderAccounting(order, salt, orderId);
    }

    function requestOrderWithPermit(
        OrderRequest calldata order,
        bytes32 salt,
        address permitToken,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenOrdersNotPaused {
        if (order.quantityIn == 0) revert ZeroValue();
        _checkRole(ASSETTOKEN_ROLE, order.assetToken);
        _checkRole(PAYMENTTOKEN_ROLE, order.paymentToken);
        bytes32 orderId = getOrderIdFromOrderRequest(order, salt);
        if (_orders[orderId].remainingOrder > 0) revert DuplicateOrder();

        IERC20Permit(permitToken).safePermit(msg.sender, address(this), value, deadline, v, r, s);
        _requestOrderAccounting(order, salt, orderId);
    }

    function fillOrder(OrderRequest calldata order, bytes32 salt, uint256 fillAmount, uint256 receivedAmount)
        external
        onlyRole(OPERATOR_ROLE)
    {
        if (fillAmount == 0) revert ZeroValue();
        bytes32 orderId = getOrderIdFromOrderRequest(order, salt);
        OrderState memory orderState = _orders[orderId];
        if (orderState.remainingOrder == 0) revert OrderNotFound();
        if (fillAmount > orderState.remainingOrder) revert AmountTooLarge();

        emit OrderFill(orderId, order.recipient, fillAmount, receivedAmount);
        _fillOrderAccounting(order, orderId, orderState, fillAmount, receivedAmount, fillAmount);
    }

    function requestCancel(OrderRequest calldata order, bytes32 salt) external {
        if (order.recipient != msg.sender) revert NotRecipient();
        bytes32 orderId = getOrderIdFromOrderRequest(order, salt);
        uint256 remainingOrder = _orders[orderId].remainingOrder;
        if (remainingOrder == 0) revert OrderNotFound();

        emit CancelRequested(orderId, order.recipient);
    }

    function cancelOrder(OrderRequest calldata order, bytes32 salt, string calldata reason)
        external
        onlyRole(OPERATOR_ROLE)
    {
        bytes32 orderId = getOrderIdFromOrderRequest(order, salt);
        OrderState memory orderState = _orders[orderId];
        if (orderState.remainingOrder == 0) revert OrderNotFound();

        emit OrderCancelled(orderId, order.recipient, reason);
        _deleteOrder(orderId);
        _cancelOrderAccounting(order, orderId, orderState);
    }

    function _deleteOrder(bytes32 orderId) internal {
        delete _orders[orderId];
        numOpenOrders--;
    }

    function _requestOrderAccounting(OrderRequest calldata order, bytes32 salt, bytes32 orderId) internal virtual;

    function _fillOrderAccounting(
        OrderRequest calldata order,
        bytes32 orderId,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256 claimPaymentAmount
    ) internal virtual;

    function _cancelOrderAccounting(OrderRequest calldata order, bytes32 orderId, OrderState memory orderState)
        internal
        virtual;
}
