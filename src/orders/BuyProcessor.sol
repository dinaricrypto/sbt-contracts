// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "prb-math/Common.sol" as PrbMath;
import {OrderProcessor, ITokenLockCheck} from "./OrderProcessor.sol";
import {FeeLib} from "../FeeLib.sol";

/// @notice Contract managing market purchase orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/BuyProcessor.sol)
/// This order processor emits market orders to buy the underlying asset that are good until cancelled
/// Fees are calculated upfront and held back from the order amount
/// The payment is escrowed until the order is filled or cancelled
/// Payment is automatically refunded if the order is cancelled
/// Implicitly assumes that asset tokens are dShare and can be minted
contract BuyProcessor is OrderProcessor {
    error LimitPriceNotSet();
    error OrderFillBelowLimitPrice();

    constructor(
        address _owner,
        address _treasury,
        uint64 _perOrderFee,
        uint24 _percentageFeeRate,
        ITokenLockCheck _tokenLockCheck
    ) OrderProcessor(_owner, _treasury, _perOrderFee, _percentageFeeRate, _tokenLockCheck) {}

    /// ------------------ Fee Helpers ------------------ ///

    /// @notice Get the raw input value and fees that produce a final order value
    /// @param token Payment token for order
    /// @param orderValue Final order value
    /// @return inputValue Total input value subject to fees
    /// @return flatFee Flat fee for order
    /// @return percentageFee Percentage fee for order
    function getInputValueForOrderValue(address token, uint256 orderValue)
        external
        view
        returns (uint256 inputValue, uint256 flatFee, uint256 percentageFee)
    {
        // load fee rate
        uint24 _percentageFeeRate = percentageFeeRate;
        // Calculate input value after flat fee
        uint256 recoveredValue = FeeLib.recoverInputValueFromRemaining(orderValue, _percentageFeeRate);
        // Calculate fees
        percentageFee = FeeLib.percentageFeeForValue(recoveredValue, _percentageFeeRate);
        flatFee = FeeLib.flatFeeForOrder(token, perOrderFee);
        // Calculate raw input value
        inputValue = recoveredValue + flatFee;
    }

    /// ------------------ Order Lifecycle ------------------ ///

    function _requestOrderAccounting(bytes32, Order calldata order, uint256) internal virtual override {
        // Ensure that price is set for limit orders
        if (order.orderType == OrderType.LIMIT && order.price == 0) revert LimitPriceNotSet();
    }

    function _fillOrderAccounting(
        bytes32,
        Order calldata order,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount
    ) internal virtual override returns (uint256 paymentEarned, uint256 feesEarned) {
        // For limit orders, ensure that the received amount is greater or equal to fill amount / limit price, order price has ether decimals
        if (order.orderType == OrderType.LIMIT && receivedAmount < PrbMath.mulDiv(fillAmount, 1 ether, order.price)) {
            revert OrderFillBelowLimitPrice();
        }

        paymentEarned = fillAmount;
        // Fees - earn the flat fee if first fill, then earn percentage fee on the fill
        feesEarned = 0;
        if (orderState.feesPaid == 0) {
            feesEarned = orderState.flatFee;
        }
        uint256 estimatedTotalFees =
            FeeLib.estimateTotalFees(orderState.flatFee, orderState.percentageFeeRate, order.paymentTokenQuantity);
        uint256 totalPercentageFees = estimatedTotalFees - orderState.flatFee;
        feesEarned += PrbMath.mulDiv(totalPercentageFees, fillAmount, order.paymentTokenQuantity);
    }

    /// @inheritdoc OrderProcessor
    function _cancelOrderAccounting(bytes32, Order calldata order, OrderState memory orderState)
        internal
        virtual
        override
        returns (uint256 refund)
    {
        uint256 totalFees =
            FeeLib.estimateTotalFees(orderState.flatFee, orderState.percentageFeeRate, order.paymentTokenQuantity);
        // If no fills, then full refund
        refund = orderState.remainingOrder + totalFees;
        if (refund < order.paymentTokenQuantity + totalFees) {
            // Refund remaining order and fees
            refund -= orderState.feesPaid;
        }
    }
}