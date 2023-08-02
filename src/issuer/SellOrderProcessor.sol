// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import {OrderProcessor} from "./OrderProcessor.sol";
import {IMintBurn} from "../IMintBurn.sol";

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
    /// @dev orderId => percentageFees
    mapping(bytes32 => uint64) private _orderPercentageFeeRates;
    mapping(bytes32 => uint256) private _amountDistributed;

    /// ------------------ Order Lifecycle ------------------ ///

    /// @inheritdoc OrderProcessor
    function _requestOrderAccounting(bytes32 id, OrderRequest calldata orderRequest)
        internal
        virtual
        override
        returns (OrderConfig memory orderConfig)
    {
        // Check if fee contract is set
        if (address(orderFees) != address(0)) {
            // Accumulate initial flat fee obligation
            _feesEarned[id] = orderFees.flatFeeForOrder(orderRequest.paymentToken);
            // store current percentage fee rate for order
            _orderPercentageFeeRates[id] = orderFees.percentageFeeRate();
        }

        // Construct order
        orderConfig = OrderConfig({
            // Sell order
            sell: true,
            // Market order
            orderType: OrderType.MARKET,
            assetTokenQuantity: orderRequest.quantityIn,
            paymentTokenQuantity: 0,
            price: orderRequest.price,
            // Good until cancelled
            tif: TIF.GTC
        });

        // Escrow asset for sale
        IERC20(orderRequest.assetToken).safeTransferFrom(msg.sender, address(this), orderRequest.quantityIn);
    }

    /// @inheritdoc OrderProcessor
    function _fillOrderAccounting(
        bytes32 id,
        Order calldata order,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount
    ) internal virtual override {
        // Retrieve the flat fee already earned for this order
        uint256 previousFeesEarned = _feesEarned[id];

        // Calculate the total received so far, including the current fill
        uint256 totalReceived = orderState.received + receivedAmount;

        // Determine the subtotal used to calculate the percentage fee
        uint256 subtotal = 0;
        if (orderState.received < previousFeesEarned) {
            // If the flat fee hasn't been fully covered yet, only consider the amount over it
            if (totalReceived > previousFeesEarned) {
                subtotal = totalReceived - previousFeesEarned;
            }
        } else {
            // If the flat fee has been fully covered, the subtotal is the entire fill amount
            subtotal = receivedAmount;
        }

        // Calculate the percentage fee on the subtotal
        uint256 collection = 0;
        if (subtotal > 0) {
            uint256 precentageFeeRate = _orderPercentageFeeRates[id];
            if (precentageFeeRate != 0) {
                collection = PrbMath.mulDiv18(subtotal, precentageFeeRate);
            }
        }

        // Calculate the total fees earned so far
        uint256 feesEarned = previousFeesEarned + collection;

        // Calculate the remaining order after this fill
        uint256 remainingOrder = orderState.remainingOrder - fillAmount;

        // Update or delete the total fees earned for this order, depending on whether the order is fully filled
        if (remainingOrder == 0) {
            delete _feesEarned[id];
        } else {
            if (collection > 0) {
                _feesEarned[id] = feesEarned;
            }
        }

        // Burn the filled quantity from the asset token
        IMintBurn(order.assetToken).burn(fillAmount);

        // Transfer the received amount from the filler to this contract
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), receivedAmount);

        // Calculate the proceeds by subtracting the collected fees from the received amount
        uint256 amountToDistribute = receivedAmount - collection;

        // Distribute the proceeds and fees
        _distributeProceeds(order.paymentToken, order.recipient, amountToDistribute, collection);

        // Track the amount distributed so far
        _amountDistributed[id] += amountToDistribute + collection;

        // If the order is fully filled, delete the record of the amount distributed
        if (remainingOrder == 0) {
            delete _amountDistributed[id];
        }
    }

    /// @inheritdoc OrderProcessor
    function _cancelOrderAccounting(bytes32 id, Order calldata order, OrderState memory orderState)
        internal
        virtual
        override
    {
        // Calculate refund amount. By default, it is the order quantity minus the amount already distributed.
        uint256 refund = order.quantityIn - _amountDistributed[id];

        // If the order has not been filled at all, refund the full order quantity
        if (orderState.remainingOrder == order.quantityIn) {
            refund = order.quantityIn;
        } else {
            // If the order has been partially filled, distribute the proceeds and fees for the filled portion,
            // and set the refund to be the remaining unfilled order quantity
            _distributeProceeds(order.paymentToken, order.recipient, orderState.received, _feesEarned[id]);
            refund = orderState.remainingOrder;
        }

        // Clear the fee and distribution state for this order
        delete _feesEarned[id];
        delete _amountDistributed[id];

        // Refund the remaining asset token back to the order requester
        IERC20(order.assetToken).safeTransfer(orderState.requester, refund);
    }

    /// @dev Distributes the proceeds from a filled order.
    /// @param paymentToken The address of the token used for payment in the order.
    /// @param recipient The address to receive the proceeds from the order.
    /// @param proceeds The amount of the order proceeds to distribute to the recipient.
    /// @param fees The amount of fees to distribute to the treasury.
    function _distributeProceeds(address paymentToken, address recipient, uint256 proceeds, uint256 fees) private {
        // If there are proceeds from the order, transfer them to the recipient
        if (proceeds > 0) {
            IERC20(paymentToken).safeTransfer(recipient, proceeds);
        }
        // If there are fees from the order, transfer them to the treasury
        if (fees > 0) {
            IERC20(paymentToken).safeTransfer(treasury, fees);
        }
    }
}
