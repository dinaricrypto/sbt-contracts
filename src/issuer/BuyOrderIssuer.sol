// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import "./OrderProcessor.sol";
import "../IMintBurn.sol";

/// @notice Contract managing swap market purchase orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/OrderRequestIssuer.sol)
contract BuyOrderIssuer is OrderProcessor {
    using SafeERC20 for IERC20;
    // This contract handles the submission and fulfillment of orders

    // 1. Order submitted and payment/asset escrowed
    // 2. Order fulfilled, escrow claimed, assets minted/burned

    // Fees are transfered when an order is closed (fulfilled or cancelled)

    struct FeeState {
        uint256 remainingPercentageFees;
        uint256 feesEarned;
    }

    error OrderTooSmall();

    mapping(bytes32 => FeeState) private _feeState;

    function getOrderRequestForOrder(Order calldata order) public pure override returns (OrderRequest memory) {
        return OrderRequest({
            recipient: order.recipient,
            assetToken: order.assetToken,
            paymentToken: order.paymentToken,
            quantityIn: order.paymentTokenQuantity + order.fee
        });
    }

    function getFeesForOrder(address token, uint256 amount)
        public
        view
        returns (uint256 flatFee, uint256 percentageFee)
    {
        if (address(orderFees) == address(0)) {
            return (0, 0);
        }

        flatFee = orderFees.flatFeeForOrder(token);
        if (amount > flatFee) {
            percentageFee = orderFees.percentageFeeOnRemainingValue(amount - flatFee);
        } else {
            percentageFee = 0;
        }
    }

    function getInputValueForOrderValue(address token, uint256 orderValue) external view returns (uint256) {
        if (address(orderFees) == address(0)) {
            return orderValue;
        }
        uint256 flatFee = orderFees.flatFeeForOrder(token);
        uint256 recoveredValue = orderFees.recoverInputValueFromFeeOnRemaining(orderValue);
        return recoveredValue + flatFee;
    }

    function _requestOrderAccounting(OrderRequest calldata order, bytes32 salt, bytes32 orderId)
        internal
        virtual
        override
    {
        // Determine fees as if fees were added to order value
        (uint256 flatFee, uint256 percentageFee) = getFeesForOrder(order.paymentToken, order.quantityIn);
        uint256 totalFees = flatFee + percentageFee;
        if (totalFees >= order.quantityIn) revert OrderTooSmall();

        _feeState[orderId] = FeeState({remainingPercentageFees: percentageFee, feesEarned: flatFee});
        uint256 orderAmount = order.quantityIn - totalFees;
        _orders[orderId] = OrderState({remainingOrder: orderAmount, received: 0});
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
            fee: totalFees
        });
        emit OrderRequested(orderId, order.recipient, bridgeOrderData, salt);

        // Escrow
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), order.quantityIn);
    }

    function _fillOrderAccounting(
        OrderRequest calldata order,
        bytes32 orderId,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256 claimPaymentAmount
    ) internal virtual override {
        FeeState memory feeState = _feeState[orderId];
        uint256 remainingOrder = orderState.remainingOrder - fillAmount;
        if (remainingOrder == 0) {
            emit OrderFulfilled(orderId, order.recipient);
            _deleteOrder(orderId);
            _closeOrder(orderId, order.paymentToken, feeState.remainingPercentageFees + feeState.feesEarned);
        } else {
            _orders[orderId].remainingOrder = remainingOrder;
            _orders[orderId].received = orderState.received + receivedAmount;
            uint256 collection = 0;
            if (feeState.remainingPercentageFees > 0) {
                collection = PrbMath.mulDiv(feeState.remainingPercentageFees, fillAmount, orderState.remainingOrder);
            }
            // Collect fees
            if (collection > 0) {
                _feeState[orderId].remainingPercentageFees = feeState.remainingPercentageFees - collection;
                _feeState[orderId].feesEarned = feeState.feesEarned + collection;
            }
        }

        // Mint asset
        IMintBurn(order.assetToken).mint(order.recipient, receivedAmount);
        // Claim payment
        if (claimPaymentAmount > 0) {
            IERC20(order.paymentToken).safeTransfer(msg.sender, claimPaymentAmount);
        }
    }

    function _cancelOrderAccounting(OrderRequest calldata order, bytes32 orderId, OrderState memory orderState)
        internal
        virtual
        override
    {
        // if no fills, then full refund
        FeeState memory feeState = _feeState[orderId];
        uint256 refund = orderState.remainingOrder + feeState.remainingPercentageFees;
        if (refund + feeState.feesEarned == order.quantityIn) {
            _closeOrder(orderId, order.paymentToken, 0);
            refund = order.quantityIn;
        } else {
            _closeOrder(orderId, order.paymentToken, feeState.feesEarned);
        }

        // Return Escrow
        IERC20(order.paymentToken).safeTransfer(order.recipient, refund);
    }

    function _closeOrder(bytes32 orderId, address paymentToken, uint256 feesEarned) internal virtual {
        delete _feeState[orderId];

        if (feesEarned > 0) {
            IERC20(paymentToken).safeTransfer(treasury, feesEarned);
        }
    }
}
