// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SafeERC20, IERC20, IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import "./Issuer.sol";
import "../IMintBurn.sol";

/// @notice Contract managing direct market buy swap orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/issuer/DirectBuyIssuer.sol)
contract DirectBuyIssuer is Issuer {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Permit;
    // This contract handles the submission and fulfillment of orders

    // 1. Order submitted and payment escrowed
    // 2. Payment taken
    // 3. Order fulfilled, fees claimed, assets minted

    struct BuyOrder {
        address recipient;
        address assetToken;
        address paymentToken;
        uint256 quantityIn;
    }

    struct OrderState {
        uint256 remainingEscrow;
        uint256 remainingOrder;
        uint256 remainingFees;
        uint256 totalReceived;
    }

    error ZeroValue();
    error NotRecipient();
    error AmountTooLarge();
    error OrderNotFound();
    error DuplicateOrder();
    error Paused();
    error OrderTooSmall();

    event OrderTaken(bytes32 indexed orderId, address indexed recipient, uint256 amount);

    bytes32 private constant ORDERTICKET_TYPE_HASH = keccak256(
        "OrderTicket(bytes32 salt,address recipient,address assetToken,address paymentToken,uint256 quantityIn"
    );

    /// @dev unfilled orders
    mapping(bytes32 => OrderState) private _orders;

    function getOrderIdFromBuyOrder(BuyOrder memory order, bytes32 salt) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDERTICKET_TYPE_HASH, salt, order.recipient, order.assetToken, order.paymentToken, order.quantityIn
            )
        );
    }

    function getOrderId(Order calldata order, bytes32 salt) external pure returns (bytes32) {
        return getOrderIdFromBuyOrder(getBuyOrderFromOrder(order), salt);
    }

    function getBuyOrderFromOrder(Order calldata order) public pure returns (BuyOrder memory) {
        return BuyOrder({
            recipient: order.recipient,
            assetToken: order.assetToken,
            paymentToken: order.paymentToken,
            quantityIn: order.paymentTokenQuantity + order.fee
        });
    }

    function isOrderActive(bytes32 id) external view returns (bool) {
        return _orders[id].remainingOrder > 0;
    }

    function getRemainingEscrow(bytes32 id) external view returns (uint256) {
        return _orders[id].remainingEscrow;
    }

    function getRemainingOrder(bytes32 id) external view returns (uint256) {
        return _orders[id].remainingOrder;
    }

    function getTotalReceived(bytes32 id) external view returns (uint256) {
        return _orders[id].totalReceived;
    }

    function requestOrder(BuyOrder calldata order, bytes32 salt) public {
        _requestOrderAccounting(order, salt);

        // Escrow payment
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), order.quantityIn);
    }

    function requestOrderWithPermit(
        BuyOrder calldata order,
        bytes32 salt,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _requestOrderAccounting(order, salt);

        // Escrow payment
        IERC20Permit(order.paymentToken).safePermit(msg.sender, address(this), value, deadline, v, r, s);
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), order.quantityIn);
    }

    function takeOrder(BuyOrder calldata order, bytes32 salt, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        if (amount == 0) revert ZeroValue();
        bytes32 orderId = getOrderIdFromBuyOrder(order, salt);
        OrderState memory orderState = _orders[orderId];
        if (amount > orderState.remainingEscrow) revert AmountTooLarge();

        _orders[orderId].remainingEscrow = orderState.remainingEscrow - amount;
        emit OrderTaken(orderId, order.recipient, amount);

        // Claim payment
        IERC20(order.paymentToken).safeTransfer(msg.sender, amount);
    }

    function fillOrder(BuyOrder calldata order, bytes32 salt, uint256 spendAmount, uint256 receivedAmount)
        external
        onlyRole(OPERATOR_ROLE)
    {
        if (spendAmount == 0) revert ZeroValue();
        bytes32 orderId = getOrderIdFromBuyOrder(order, salt);
        OrderState memory orderState = _orders[orderId];
        if (orderState.remainingOrder == 0) revert OrderNotFound();
        if (
            spendAmount > orderState.remainingOrder
                || orderState.remainingOrder - spendAmount < orderState.remainingEscrow
        ) revert AmountTooLarge();

        emit OrderFill(orderId, order.recipient, spendAmount, receivedAmount);
        uint256 remainingUnspent = orderState.remainingOrder - spendAmount;
        uint256 collection = 0;
        if (remainingUnspent == 0) {
            delete _orders[orderId];
            numOpenOrders--;
            collection = orderState.remainingFees;
            emit OrderFulfilled(orderId, order.recipient);
        } else {
            _orders[orderId].remainingOrder = remainingUnspent;
            _orders[orderId].totalReceived = orderState.totalReceived + receivedAmount;
            if (orderState.remainingFees > 0) {
                collection = PrbMath.mulDiv(orderState.remainingFees, spendAmount, orderState.remainingOrder);
                _orders[orderId].remainingFees = orderState.remainingFees - collection;
            }
        }

        // Collect fees from tokenIn
        if (collection > 0) {
            IERC20(order.paymentToken).safeTransfer(treasury, collection);
        }
        // Mint asset
        IMintBurn(order.assetToken).mint(order.recipient, receivedAmount);
    }

    function requestCancel(BuyOrder calldata order, bytes32 salt) external {
        if (order.recipient != msg.sender) revert NotRecipient();
        bytes32 orderId = getOrderIdFromBuyOrder(order, salt);
        uint256 remainingOrder = _orders[orderId].remainingOrder;
        if (remainingOrder == 0) revert OrderNotFound();

        emit CancelRequested(orderId, order.recipient);
    }

    function cancelOrder(BuyOrder calldata order, bytes32 salt, string calldata reason)
        external
        onlyRole(OPERATOR_ROLE)
    {
        bytes32 orderId = getOrderIdFromBuyOrder(order, salt);
        OrderState memory orderState = _orders[orderId];
        if (orderState.remainingOrder == 0) revert OrderNotFound();

        delete _orders[orderId];
        numOpenOrders--;
        emit OrderCancelled(orderId, order.recipient, reason);

        // Return Escrow
        IERC20(order.paymentToken).safeTransfer(order.recipient, orderState.remainingEscrow);
    }

    function _requestOrderAccounting(BuyOrder calldata order, bytes32 salt) internal {
        if (ordersPaused) revert Paused();
        if (order.quantityIn == 0) revert ZeroValue();
        _checkRole(ASSETTOKEN_ROLE, order.assetToken);
        _checkRole(PAYMENTTOKEN_ROLE, order.paymentToken);
        bytes32 orderId = getOrderIdFromBuyOrder(order, salt);
        if (_orders[orderId].remainingOrder > 0) revert DuplicateOrder();

        uint256 collection = getFeesForOrder(order.assetToken, false, order.quantityIn);
        if (collection >= order.quantityIn) revert OrderTooSmall();

        uint256 orderAmount = order.quantityIn - collection;
        _orders[orderId] = OrderState({
            remainingEscrow: orderAmount,
            remainingOrder: orderAmount,
            remainingFees: collection,
            totalReceived: 0
        });
        numOpenOrders++;
        Order memory bridgeOrderData = Order({
            recipient: order.recipient,
            assetToken: order.assetToken,
            paymentToken: order.paymentToken,
            sell: false,
            orderType: OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: orderAmount,
            price: 0,
            tif: TIF.GTC,
            fee: collection
        });
        emit OrderRequested(orderId, order.recipient, bridgeOrderData, salt);
    }
}
