// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import "./OrderProcessor.sol";
import "../IMintBurn.sol";

/// @notice Contract managing swap market purchase orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/SellOrderProcessor.sol)
contract SellOrderProcessor is OrderProcessor {
    using SafeERC20 for IERC20;
    // This contract handles the submission and fulfillment of orders

    // 1. Order submitted and payment/asset escrowed
    // 2. Order fulfilled, escrow claimed, assets minted/burned

    // Fees are transfered when an order is closed (fulfilled or cancelled)

    mapping(bytes32 => uint256) private _feesEarned;

    function getOrderRequestForOrder(Order calldata order) public pure override returns (OrderRequest memory) {
        return OrderRequest({
            recipient: order.recipient,
            assetToken: order.assetToken,
            paymentToken: order.paymentToken,
            quantityIn: order.paymentTokenQuantity
        });
    }

    function getFlatFeeForOrder(address token) public view returns (uint256) {
        if (address(orderFees) == address(0)) return 0;
        return orderFees.flatFeeForOrder(token);
    }

    function getPercentageFeeForOrder(uint256 value) public view returns (uint256) {
        if (address(orderFees) == address(0)) return 0;
        return orderFees.percentageFeeForValue(value);
    }

    function _requestOrderAccounting(OrderRequest calldata order, bytes32 salt, bytes32 orderId)
        internal
        virtual
        override
    {
        // Determine fees as if fees were added to order value
        uint256 flatFee = getFlatFeeForOrder(order.paymentToken);

        _feesEarned[orderId] = flatFee;
        _orders[orderId] = OrderState({remainingOrder: order.quantityIn, received: 0});
        numOpenOrders++;
        Order memory bridgeOrderData = Order({
            recipient: order.recipient,
            assetToken: order.assetToken,
            paymentToken: order.paymentToken,
            sell: true,
            orderType: OrderType.MARKET,
            assetTokenQuantity: order.quantityIn,
            paymentTokenQuantity: 0,
            price: 0,
            tif: TIF.GTC,
            fee: 0
        });
        emit OrderRequested(orderId, order.recipient, bridgeOrderData, salt);

        // Escrow
        IERC20(order.assetToken).safeTransferFrom(msg.sender, address(this), order.quantityIn);
    }

    function _fillOrderAccounting(
        OrderRequest calldata order,
        bytes32 orderId,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256
    ) internal virtual override {
        // accum fees each order then take all at end
        uint256 collection = getPercentageFeeForOrder(receivedAmount);
        uint256 feesEarned = _feesEarned[orderId] + collection;
        //
        uint256 remainingOrder = orderState.remainingOrder - fillAmount;
        uint256 totalReceived = orderState.received + receivedAmount;
        if (remainingOrder == 0) {
            emit OrderFulfilled(orderId, order.recipient);
            _deleteOrder(orderId);
            delete _feesEarned[orderId];
        } else {
            _orders[orderId].remainingOrder = remainingOrder;
            _orders[orderId].received = totalReceived;
            // Collect fees
            if (collection > 0) {
                _feesEarned[orderId] = feesEarned;
            }
        }

        // Burn asset
        IMintBurn(order.assetToken).burn(fillAmount);
        // Move money
        IERC20(order.paymentToken).safeTransfer(msg.sender, receivedAmount);
        // Distribute
        if (remainingOrder == 0) {
            _distributeProceeds(order.paymentToken, order.recipient, totalReceived, feesEarned);
        }
    }

    function _cancelOrderAccounting(OrderRequest calldata order, bytes32 orderId, OrderState memory orderState)
        internal
        virtual
        override
    {
        // if no fills, then full refund
        uint256 refund;
        if (orderState.remainingOrder == order.quantityIn) {
            refund = order.quantityIn;
        } else {
            _distributeProceeds(order.paymentToken, order.recipient, orderState.received, _feesEarned[orderId]);
            refund = orderState.remainingOrder;
        }
        delete _feesEarned[orderId];

        // Return Escrow
        IERC20(order.assetToken).safeTransfer(order.recipient, refund);
    }

    function _distributeProceeds(address paymentToken, address recipient, uint256 totalReceived, uint256 feesEarned)
        internal
        virtual
    {
        uint256 proceeds = 0;
        uint256 collection = 0;
        if (totalReceived > feesEarned) {
            proceeds = totalReceived - feesEarned;
            collection = feesEarned;
        } else {
            collection = totalReceived;
        }

        if (proceeds > 0) {
            IERC20(paymentToken).safeTransfer(recipient, proceeds);
        }
        if (collection > 0) {
            IERC20(paymentToken).safeTransfer(treasury, collection);
        }
    }
}
