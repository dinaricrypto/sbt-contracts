// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import {OrderProcessor} from "./OrderProcessor.sol";
import {IMintBurn} from "../IMintBurn.sol";

/// @notice Contract managing market purchase orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/BuyOrderIssuer.sol)
/// This order processor emits market orders to buy the underlying asset that are good until cancelled
/// Fees are calculated upfront and held back from the order amount
/// The payment is escrowed until the order is filled or cancelled
/// Payment is automatically refunded if the order is cancelled
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

    /// @dev Order is too small to pay fees
    error OrderTooSmall();

    /// ------------------ State ------------------ ///

    /// @dev orderId => FeeState
    mapping(bytes32 => FeeState) private _feeState;

    /// ------------------ Fee Helpers ------------------ ///

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

    /// @notice Get the raw input value and fees that produce a final order value
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
    function _requestOrderAccounting(bytes32 id, OrderRequest calldata orderRequest)
        internal
        virtual
        override
        returns (OrderConfig memory orderConfig)
    {
        // Determine fees
        (uint256 flatFee, uint256 percentageFee) = getFeesForOrder(orderRequest.paymentToken, orderRequest.quantityIn);
        uint256 totalFees = flatFee + percentageFee;
        // Fees must not exceed order input value
        if (totalFees >= orderRequest.quantityIn) revert OrderTooSmall();

        // Initialize fee state for order
        _feeState[id] = FeeState({remainingPercentageFees: percentageFee, feesEarned: flatFee});

        // Construct order specification
        orderConfig = OrderConfig({
            // Buy order
            sell: false,
            // Market order
            orderType: OrderType.MARKET,
            assetTokenQuantity: 0,
            // Hold fees back from order amount
            paymentTokenQuantity: orderRequest.quantityIn - totalFees,
            price: orderRequest.price,
            // Good until cancelled
            tif: TIF.GTC
        });

        // Escrow payment for purchase
        IERC20(orderRequest.paymentToken).safeTransferFrom(msg.sender, address(this), orderRequest.quantityIn);
    }

    /// @inheritdoc OrderProcessor
    // slither-disable-next-line dead-code
    function _fillOrderAccounting(
        bytes32 id,
        Order calldata order,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount
    ) internal virtual override {
        // Calculate fees and mint asset
        _fillBuyOrder(id, order, orderState, fillAmount, receivedAmount);

        // Claim payment
        IERC20(order.paymentToken).safeTransfer(msg.sender, fillAmount);
    }

    /// @dev Fill buy order accounting and mint asset
    function _fillBuyOrder(
        bytes32 id,
        Order calldata order,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount
    ) internal virtual {
        FeeState memory feeState = _feeState[id];
        uint256 remainingOrder = orderState.remainingOrder - fillAmount;
        // If order is done, close order and transfer fees
        if (remainingOrder == 0) {
            _closeOrder(id, order.paymentToken, feeState.remainingPercentageFees + feeState.feesEarned);
        } else {
            // Otherwise accumulate fees for fill
            // Calculate fees
            uint256 collection = 0;
            if (feeState.remainingPercentageFees > 0) {
                // fee = remainingPercentageFees * fillAmount / remainingOrder
                collection = PrbMath.mulDiv(feeState.remainingPercentageFees, fillAmount, orderState.remainingOrder);
            }
            // Update fee state
            if (collection > 0) {
                _feeState[id].remainingPercentageFees = feeState.remainingPercentageFees - collection;
                _feeState[id].feesEarned = feeState.feesEarned + collection;
            }
        }

        // Mint asset
        IMintBurn(order.assetToken).mint(order.recipient, receivedAmount);
    }

    /// @inheritdoc OrderProcessor
    function _cancelOrderAccounting(bytes32 id, Order calldata order, OrderState memory orderState)
        internal
        virtual
        override
    {
        FeeState memory feeState = _feeState[id];
        // If no fills, then full refund
        // This addition is required to check for any fills
        uint256 refund = orderState.remainingOrder + feeState.remainingPercentageFees;
        // If any fills, then orderState.remainingOrder would not be large enough to satisfy this condition
        // feesEarned is always needed to recover flat fee
        if (refund + feeState.feesEarned == order.quantityIn) {
            _closeOrder(id, order.paymentToken, 0);
            // Refund full payment
            refund = order.quantityIn;
        } else {
            // Otherwise close order and transfer fees
            _closeOrder(id, order.paymentToken, feeState.feesEarned);
        }

        // Return escrow
        IERC20(order.paymentToken).safeTransfer(order.recipient, refund);
    }

    /// @dev Close order and transfer fees
    function _closeOrder(bytes32 id, address paymentToken, uint256 feesEarned) private {
        // Clear fee state
        delete _feeState[id];

        // Transfer earneds fees to treasury
        if (feesEarned > 0) {
            IERC20(paymentToken).safeTransfer(treasury, feesEarned);
        }
    }
}
