// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import {OrderProcessor} from "./OrderProcessor.sol";
import {IMintBurn} from "../IMintBurn.sol";

/// @notice Contract managing market purchase orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/BuyOrderIssuer.sol)
/// Implicitly assumes that asset tokens are BridgedERC20 and can be minted
contract BuyOrderIssuer is OrderProcessor {
    // Handle token transfers safely
    using SafeERC20 for IERC20;

    /// ------------------ Types ------------------ ///

    struct FeeState {
        // Percentage fees are calculated upfront and accumulated as order is filled
        uint256 remainingPercentageFees;
        // Total fees earned including flat fee
        uint256 feesEarned;
    }

    error OrderTooSmall();

    /// ------------------ State ------------------ ///

    /// @dev orderId => FeeState
    mapping(bytes32 => FeeState) private _feeState;

    /// ------------------ Getters ------------------ ///

    /// @inheritdoc OrderProcessor
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
    /// @param inputValue Total input value subject to fees
    /// @return flatFee Flat fee for order
    /// @return percentageFee Percentage fee for order
    /// @dev Fees zero if no orderFees contract is set
    function getFeesForOrder(address token, uint256 inputValue)
        public
        view
        returns (uint256 flatFee, uint256 percentageFee)
    {
        // Check if fee contract is set
        if (address(orderFees) == address(0)) {
            return (0, 0);
        }

        // Calculate fees
        flatFee = orderFees.flatFeeForOrder(token);
        // If input value is greater than flat fee, calculate percentage fee on remaining value
        if (inputValue > flatFee) {
            percentageFee = orderFees.percentageFeeForValue(inputValue - flatFee);
        } else {
            percentageFee = 0;
        }
    }

    /// @notice Get the raw input value and fees for a final order value
    /// @param token Payment token for order
    /// @param orderValue Final order value
    /// @return inputValue Total input value subject to fees
    /// @return flatFee Flat fee for order
    /// @return percentageFee Percentage fee for order
    /// @dev Fees zero if no orderFees contract is set
    function getInputValueForOrderValue(address token, uint256 orderValue)
        external
        view
        returns (uint256 inputValue, uint256 flatFee, uint256 percentageFee)
    {
        // Check if fee contract is set
        if (address(orderFees) == address(0)) {
            return (orderValue, 0, 0);
        }

        // Calculate input value after flat fee
        uint256 recoveredValue = orderFees.recoverInputValueFromRemaining(orderValue);
        // Calculate fees
        percentageFee = orderFees.percentageFeeForValue(recoveredValue);
        flatFee = orderFees.flatFeeForOrder(token);
        // Calculate raw input value
        inputValue = recoveredValue + flatFee;
    }

    /// ------------------ Order Lifecycle ------------------ ///

    /// @inheritdoc OrderProcessor
    function _requestOrderAccounting(OrderRequest calldata orderRequest, bytes32 orderId)
        internal
        virtual
        override
        returns (Order memory order)
    {
        // Determine fees
        (uint256 flatFee, uint256 percentageFee) = getFeesForOrder(orderRequest.paymentToken, orderRequest.quantityIn);
        uint256 totalFees = flatFee + percentageFee;
        // Fees must not exceed order input value
        if (totalFees >= orderRequest.quantityIn) revert OrderTooSmall();

        // Initialize fee state for order
        _feeState[orderId] = FeeState({remainingPercentageFees: percentageFee, feesEarned: flatFee});

        // Construct order
        order = Order({
            recipient: orderRequest.recipient,
            assetToken: orderRequest.assetToken,
            paymentToken: orderRequest.paymentToken,
            sell: false,
            orderType: OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: orderRequest.quantityIn - totalFees,
            price: 0,
            tif: TIF.GTC,
            fee: totalFees
        });

        // Escrow payment for purchase
        IERC20(orderRequest.paymentToken).safeTransferFrom(msg.sender, address(this), orderRequest.quantityIn);
    }

    /// @inheritdoc OrderProcessor
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
        // If order is done, close order and transfer fees
        if (remainingOrder == 0) {
            _closeOrder(orderId, orderRequest.paymentToken, feeState.remainingPercentageFees + feeState.feesEarned);
        } else {
            // Calculate fees
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

    /// @inheritdoc OrderProcessor
    function _cancelOrderAccounting(OrderRequest calldata orderRequest, bytes32 orderId, OrderState memory orderState)
        internal
        virtual
        override
    {
        // If no fills, then full refund
        FeeState memory feeState = _feeState[orderId];
        uint256 refund = orderState.remainingOrder + feeState.remainingPercentageFees;
        if (refund + feeState.feesEarned == orderRequest.quantityIn) {
            _closeOrder(orderId, orderRequest.paymentToken, 0);
            refund = orderRequest.quantityIn;
        } else {
            _closeOrder(orderId, orderRequest.paymentToken, feeState.feesEarned);
        }

        // Return escrow
        IERC20(orderRequest.paymentToken).safeTransfer(orderRequest.recipient, refund);
    }

    /// @dev Close order and transfer fees
    function _closeOrder(bytes32 orderId, address paymentToken, uint256 feesEarned) private {
        // Clear fee state
        delete _feeState[orderId];

        // Transfer fees
        if (feesEarned > 0) {
            IERC20(paymentToken).safeTransfer(treasury, feesEarned);
        }
    }
}
