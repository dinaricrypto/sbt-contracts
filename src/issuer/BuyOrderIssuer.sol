// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SafeERC20, IERC20, IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import "./Issuer.sol";
import "../IMintBurn.sol";

/// @notice Contract managing swap market purchase orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/BuyOrderIssuer.sol)
contract BuyOrderIssuer is Issuer {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Permit;
    // This contract handles the submission and fulfillment of orders

    // 1. Order submitted and payment/asset escrowed
    // 2. Order fulfilled, escrow claimed, assets minted/burned

    // Fees are transfered when an order is closed (fulfilled or cancelled)

    struct BuyOrder {
        address recipient;
        address assetToken;
        address paymentToken;
        uint256 quantityIn;
    }

    struct OrderState {
        uint256 remainingOrder;
        uint256 remainingPercentageFees;
        uint256 feesEarned;
        uint256 received;
    }

    error ZeroValue();
    error NotRecipient();
    error OrderNotFound();
    error DuplicateOrder();
    error FillTooLarge();
    error OrderTooSmall();

    bytes32 private constant BUYORDER_TYPE_HASH =
        keccak256("BuyOrder(bytes32 salt,address recipient,address assetToken,address paymentToken,uint256 quantityIn");

    /// @dev unfilled orders
    mapping(bytes32 => OrderState) private _orders;

    function getOrderIdFromBuyOrder(BuyOrder memory order, bytes32 salt) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                BUYORDER_TYPE_HASH, salt, order.recipient, order.assetToken, order.paymentToken, order.quantityIn
            )
        );
    }

    function getOrderId(Order calldata order, bytes32 salt) external pure returns (bytes32) {
        return getOrderIdFromBuyOrder(getBuyOrderForOrder(order), salt);
    }

    function getBuyOrderForOrder(Order calldata order) public pure returns (BuyOrder memory) {
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

    function getRemainingOrder(bytes32 id) external view returns (uint256) {
        return _orders[id].remainingOrder;
    }

    function getTotalReceived(bytes32 id) external view returns (uint256) {
        return _orders[id].received;
    }

    function requestOrder(BuyOrder calldata order, bytes32 salt) public {
        _requestOrderAccounting(order, salt);

        // Escrow
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

        // Escrow
        IERC20Permit(order.paymentToken).safePermit(msg.sender, address(this), value, deadline, v, r, s);
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), order.quantityIn);
    }

    function fillOrder(BuyOrder calldata order, bytes32 salt, uint256 spendAmount, uint256 receivedAmount)
        external
        onlyRole(OPERATOR_ROLE)
    {
        if (spendAmount == 0) revert ZeroValue();
        bytes32 orderId = getOrderIdFromBuyOrder(order, salt);
        OrderState memory orderState = _orders[orderId];
        if (orderState.remainingOrder == 0) revert OrderNotFound();
        if (spendAmount > orderState.remainingOrder) revert FillTooLarge();

        emit OrderFill(orderId, order.recipient, spendAmount, receivedAmount);
        uint256 remainingOrder = orderState.remainingOrder - spendAmount;
        if (remainingOrder == 0) {
            emit OrderFulfilled(orderId, order.recipient);
            _closeOrder(orderId, order.paymentToken, orderState.remainingPercentageFees + orderState.feesEarned);
        } else {
            _orders[orderId].remainingOrder = remainingOrder;
            _orders[orderId].received = orderState.received + receivedAmount;
            uint256 collection = 0;
            if (orderState.remainingPercentageFees > 0) {
                collection = PrbMath.mulDiv(orderState.remainingPercentageFees, spendAmount, orderState.remainingOrder);
            }
            // Collect fees
            if (collection > 0) {
                _orders[orderId].remainingPercentageFees = orderState.remainingPercentageFees - collection;
                IERC20(order.paymentToken).safeTransfer(treasury, collection);
            }
        }

        // Claim payment and mint
        IERC20(order.paymentToken).safeTransfer(msg.sender, spendAmount);
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

        emit OrderCancelled(orderId, order.recipient, reason);

        // if no fills, then full refund
        uint256 refund = orderState.remainingOrder + orderState.remainingPercentageFees;
        if (refund + orderState.feesEarned == order.quantityIn) {
            _closeOrder(orderId, order.paymentToken, 0);
            refund = order.quantityIn;
        } else {
            _closeOrder(orderId, order.paymentToken, orderState.feesEarned);
        }

        // Return Escrow
        IERC20(order.paymentToken).safeTransfer(order.recipient, refund);
    }

    function _requestOrderAccounting(BuyOrder calldata order, bytes32 salt) internal whenOrdersNotPaused {
        if (order.quantityIn == 0) revert ZeroValue();
        _checkRole(ASSETTOKEN_ROLE, order.assetToken);
        _checkRole(PAYMENTTOKEN_ROLE, order.paymentToken);
        bytes32 orderId = getOrderIdFromBuyOrder(order, salt);
        if (_orders[orderId].remainingOrder > 0) revert DuplicateOrder();

        // Determine fees as if fees were added to order value
        uint256 flatFee = 0;
        uint256 percentageFee = 0;
        if (address(orderFees) != address(0)) {
            (flatFee, percentageFee) = orderFees.feesForOrderUpfront(order.assetToken, order.quantityIn);
        }
        uint256 totalFees = flatFee + percentageFee;
        if (totalFees >= order.quantityIn) revert OrderTooSmall();

        uint256 orderAmount = order.quantityIn - totalFees;
        _orders[orderId] = OrderState({
            remainingOrder: orderAmount,
            remainingPercentageFees: percentageFee,
            feesEarned: flatFee,
            received: 0
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
            tif: TIF.DAY,
            fee: totalFees
        });
        emit OrderRequested(orderId, order.recipient, bridgeOrderData, salt);
    }

    function _closeOrder(bytes32 orderId, address paymentToken, uint256 feesEarned) internal {
        delete _orders[orderId];
        numOpenOrders--;

        if (feesEarned > 0) {
            IERC20(paymentToken).safeTransfer(treasury, feesEarned);
        }
    }
}
