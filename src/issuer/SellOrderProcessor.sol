// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import {OrderProcessor} from "./OrderProcessor.sol";
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

    /// ------------------ State ------------------ ///

    /// @dev orderId => feesEarned
    mapping(bytes32 => uint256) private _feesEarned;

    constructor(address _owner, address treasury_, IOrderFees orderFees_)
        OrderProcessor(_owner, treasury_, orderFees_)
    {}

    /// ------------------ Getters ------------------ ///

    /// @notice Get flat fee for an order
    /// @param token Payment token for order
    /// @dev Fee zero if no orderFees contract is set
    function getFlatFeeForOrder(address token) public view returns (uint256) {
        // Check if fee contract is set
        if (address(orderFees) == address(0)) return 0;
        // Calculate fees
        return orderFees.flatFeeForOrder(token);
    }

    /// @notice Get percentage fee for an order
    /// @param value Value of order subject to percentage fee
    /// @dev Fee zero if no orderFees contract is set
    function getPercentageFeeForOrder(uint256 value) public view returns (uint256) {
        // Check if fee contract is set
        if (address(orderFees) == address(0)) return 0;
        // Calculate fees
        return orderFees.percentageFeeForValue(value);
    }

    /// ------------------ Order Lifecycle ------------------ ///

    /// @inheritdoc OrderProcessor
    function _requestOrderAccounting(Order calldata order, bytes32 orderId) internal virtual override {
        // Accumulate initial flat fee obligation
        _feesEarned[orderId] = getFlatFeeForOrder(order.paymentToken);

        // Escrow asset for sale
        IERC20(order.assetToken).safeTransferFrom(msg.sender, address(this), order.assetTokenQuantity);
    }

    /// @inheritdoc OrderProcessor
    function _fillOrderAccounting(
        Order calldata order,
        bytes32 orderId,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount
    ) internal virtual override {
        // Accumulate fee obligations at each sill then take all at end
        uint256 collection = getPercentageFeeForOrder(receivedAmount);
        uint256 feesEarned = _feesEarned[orderId] + collection;
        // If order completely filled, clear fee data
        uint256 remainingOrder = orderState.remainingOrder - fillAmount;
        if (remainingOrder == 0) {
            // Clear fee state
            delete _feesEarned[orderId];
        } else {
            // Update fee state with earned fees
            if (collection > 0) {
                _feesEarned[orderId] = feesEarned;
            }
        }

        // Burn asset
        IMintBurn(order.assetToken).burn(fillAmount);
        // Transfer raw proceeds of sale here
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), receivedAmount);
        // Distribute if order completely filled
        if (remainingOrder == 0) {
            _distributeProceeds(order.paymentToken, order.recipient, orderState.received + receivedAmount, feesEarned);
        }
    }

    /// @inheritdoc OrderProcessor
    function _cancelOrderAccounting(Order calldata order, bytes32 orderId, OrderState memory orderState)
        internal
        virtual
        override
    {
        // If no fills, then full refund
        uint256 refund;
        if (orderState.remainingOrder == order.assetTokenQuantity) {
            // Full refund
            refund = order.assetTokenQuantity;
        } else {
            // Otherwise distribute proceeds, take accumulated fees, and refund remaining order
            _distributeProceeds(order.paymentToken, order.recipient, orderState.received, _feesEarned[orderId]);
            // Partial refund
            refund = orderState.remainingOrder;
        }

        // Clear fee data
        delete _feesEarned[orderId];

        // Return escrow
        IERC20(order.assetToken).safeTransfer(order.recipient, refund);
    }

    /// @dev Distribute proceeds and fees
    function _distributeProceeds(address paymentToken, address recipient, uint256 totalReceived, uint256 feesEarned)
        private
    {
        // Check if accumulated fees are larger than total received
        uint256 proceeds = 0;
        uint256 collection = 0;
        if (totalReceived > feesEarned) {
            // Take fees from total received before distributing
            proceeds = totalReceived - feesEarned;
            collection = feesEarned;
        } else {
            // If accumulated fees are larger than total received, then no proceeds go to recipient
            collection = totalReceived;
        }

        // Transfer proceeds to recipient
        if (proceeds > 0) {
            IERC20(paymentToken).safeTransfer(recipient, proceeds);
        }
        // Transfer fees to treasury
        if (collection > 0) {
            IERC20(paymentToken).safeTransfer(treasury, collection);
        }
    }
}
