// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import {OrderProcessor, ITokenLockCheck} from "./OrderProcessor.sol";
import {IMintBurn} from "../IMintBurn.sol";
import {IOrderFees} from "./IOrderFees.sol";

/// @notice Contract managing market sell orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/issuer/SellOrderProcessor.sol)
/// This order processor emits market orders to sell the underlying asset that are good until cancelled
/// Fee obligations are accumulated as order is filled
/// Fees are taken from the proceeds of the sale
/// The asset token is escrowed until the order is filled or cancelled
/// The asset token is automatically refunded if the order is cancelled
/// Implicitly assumes that asset tokens are dShare and can be burned
contract SellOrderProcessor is OrderProcessor {
    using SafeERC20 for IERC20;

    constructor(address _owner, address treasury_, IOrderFees orderFees_, ITokenLockCheck tokenLockCheck_)
        OrderProcessor(_owner, treasury_, orderFees_, tokenLockCheck_)
    {}

    /// ------------------ Order Lifecycle ------------------ ///

    /// @inheritdoc OrderProcessor
    function _requestOrderAccounting(bytes32, Order calldata order, uint256) internal virtual override {
        // Transfer asset to contract
        IERC20(order.assetToken).safeTransferFrom(msg.sender, address(this), order.assetTokenQuantity);
    }

    function _fillOrderAccounting(
        bytes32,
        Order calldata,
        OrderState memory orderState,
        uint256,
        uint256 receivedAmount
    ) internal virtual override returns (uint256 paymentEarned, uint256 feesEarned) {
        // Fees - earn up to the flat fee, then earn percentage fee on the remainder
        // TODO: make sure that all fees are taken at total fill to prevent dust accumulating here
        // Determine the subtotal used to calculate the percentage fee
        uint256 subtotal = 0;
        // If the flat fee hasn't been fully covered yet, ...
        if (orderState.feesPaid < orderState.flatFee) {
            // How much of the flat fee is left to cover?
            uint256 flatFeeRemaining = orderState.flatFee - orderState.feesPaid;
            // If the amount subject to fees is greater than the remaining flat fee, ...
            if (receivedAmount > flatFeeRemaining) {
                // Earn the remaining flat fee
                feesEarned = flatFeeRemaining;
                // Calculate the subtotal by subtracting the remaining flat fee from the amount subject to fees
                subtotal = receivedAmount - flatFeeRemaining;
            } else {
                // Otherwise, earn the amount subject to fees
                feesEarned = receivedAmount;
            }
        } else {
            // If the flat fee has been fully covered, the subtotal is the entire fill amount
            subtotal = receivedAmount;
        }

        // Calculate the percentage fee on the subtotal
        if (subtotal > 0 && orderState.percentageFeeRate > 0) {
            feesEarned += PrbMath.mulDiv18(subtotal, orderState.percentageFeeRate);
        }

        paymentEarned = receivedAmount - feesEarned;
    }

    /// @inheritdoc OrderProcessor
    function _cancelOrderAccounting(bytes32, Order calldata, OrderState memory orderState)
        internal
        virtual
        override
        returns (uint256 refund)
    {
        refund = orderState.remainingOrder;
    }
}
