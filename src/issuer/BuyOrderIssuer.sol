// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import {OrderProcessor} from "./OrderProcessor.sol";
import {IMintBurn} from "../IMintBurn.sol";

/// @notice Contract managing swap market purchase orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/OrderRequestIssuer.sol)
contract BuyOrderIssuer is OrderProcessor {
    using SafeERC20 for IERC20;
    // This contract handles the submission and fulfillment of orders

    // 1. Order submitted and payment/asset escrowed
    // 2. Order fulfilled, escrow claimed, assets minted/burned

    // Fees are transfered when an order is closed (fulfilled or cancelled)

    struct FeeState {
        // Percentage fees are calculated upfront and accumulated as order is filled
        uint256 remainingPercentageFees;
        // Total fees earned including flat fee
        uint256 feesEarned;
    }

    error OrderTooSmall();

    // orderId => FeeState
    mapping(bytes32 => FeeState) private _feeState;

    /// @notice Get corresponding OrderRequest for an Order
    /// @param order Order to get OrderRequest for
    /// @return OrderRequest for Order
    function getOrderRequestForOrder(Order calldata order) public pure override returns (OrderRequest memory) {
        return OrderRequest({
            recipient: order.recipient,
            assetToken: order.assetToken,
            paymentToken: order.paymentToken,
            quantityIn: order.paymentTokenQuantity + order.fee
        });
    }

    /// @notice Get fees for an order
    /// @param token Payment token for order
    /// @param amount Amount of payment token for order
    /// @return flatFee Flat fee for order
    /// @return percentageFee Percentage fee for order
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

    /// @notice Get the raw input value for a final order value
    /// @param token Payment token for order
    /// @param orderValue Final order value
    function getInputValueForOrderValue(address token, uint256 orderValue) external view returns (uint256) {
        if (address(orderFees) == address(0)) {
            return orderValue;
        }
        uint256 flatFee = orderFees.flatFeeForOrder(token);
        uint256 recoveredValue = orderFees.recoverInputValueFromFeeOnRemaining(orderValue);
        return recoveredValue + flatFee;
    }

    function _requestOrderAccounting(OrderRequest calldata orderRequest, bytes32 salt, bytes32 orderId)
        internal
        virtual
        override
        returns (uint256 orderAmount)
    {
        // Determine fees as if fees were added to order value
        (uint256 flatFee, uint256 percentageFee) = getFeesForOrder(orderRequest.paymentToken, orderRequest.quantityIn);
        uint256 totalFees = flatFee + percentageFee;
        if (totalFees >= orderRequest.quantityIn) revert OrderTooSmall();

        _feeState[orderId] = FeeState({remainingPercentageFees: percentageFee, feesEarned: flatFee});
        orderAmount = orderRequest.quantityIn - totalFees;
        Order memory bridgeOrderData = Order({
            recipient: orderRequest.recipient,
            assetToken: orderRequest.assetToken,
            paymentToken: orderRequest.paymentToken,
            sell: false,
            orderType: OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: orderAmount,
            price: 0,
            tif: TIF.GTC,
            fee: totalFees
        });
        emit OrderRequested(orderId, orderRequest.recipient, bridgeOrderData, salt);

        // Escrow
        IERC20(orderRequest.paymentToken).safeTransferFrom(msg.sender, address(this), orderRequest.quantityIn);
    }

    function _fillOrderAccounting(
        OrderRequest calldata orderRequest,
        bytes32 orderId,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256 claimPaymentAmount
    ) internal virtual override {
        FeeState memory feeState = _feeState[orderId];
        uint256 remainingOrder = orderState.remainingOrder - fillAmount;
        if (remainingOrder == 0) {
            _closeOrder(orderId, orderRequest.paymentToken, feeState.remainingPercentageFees + feeState.feesEarned);
        } else {
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
        IMintBurn(orderRequest.assetToken).mint(orderRequest.recipient, receivedAmount);
        // Claim payment
        if (claimPaymentAmount > 0) {
            IERC20(orderRequest.paymentToken).safeTransfer(msg.sender, claimPaymentAmount);
        }
    }

    function _cancelOrderAccounting(OrderRequest calldata orderRequest, bytes32 orderId, OrderState memory orderState)
        internal
        virtual
        override
    {
        // if no fills, then full refund
        FeeState memory feeState = _feeState[orderId];
        uint256 refund = orderState.remainingOrder + feeState.remainingPercentageFees;
        if (refund + feeState.feesEarned == orderRequest.quantityIn) {
            _closeOrder(orderId, orderRequest.paymentToken, 0);
            refund = orderRequest.quantityIn;
        } else {
            _closeOrder(orderId, orderRequest.paymentToken, feeState.feesEarned);
        }

        // Return Escrow
        IERC20(orderRequest.paymentToken).safeTransfer(orderRequest.recipient, refund);
    }

    function _closeOrder(bytes32 orderId, address paymentToken, uint256 feesEarned) internal virtual {
        delete _feeState[orderId];

        if (feesEarned > 0) {
            IERC20(paymentToken).safeTransfer(treasury, feesEarned);
        }
    }
}
