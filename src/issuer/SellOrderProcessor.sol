// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import "./OrderProcessor.sol";
import "../IMintBurn.sol";

/// @notice Contract managing swap market purchase orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/issuer/SellOrderProcessor.sol)
contract SellOrderProcessor is OrderProcessor {
    using SafeERC20 for IERC20;
    // This contract handles the submission and fulfillment of orders

    // 1. Order submitted and payment/asset escrowed
    // 2. Order fulfilled, escrow claimed, assets minted/burned

    // Fees are transfered when an order is closed (fulfilled or cancelled)

    /// @dev orderId => feesEarned
    mapping(bytes32 => uint256) private _feesEarned;

    /// @inheritdoc OrderProcessor
    function getOrderRequestForOrder(Order calldata order) public pure override returns (OrderRequest memory) {
        return OrderRequest({
            recipient: order.recipient,
            assetToken: order.assetToken,
            paymentToken: order.paymentToken,
            quantityIn: order.assetTokenQuantity
        });
    }

    /// @notice Get flat fee for an order
    /// @param token Payment token for order
    function getFlatFeeForOrder(address token) public view returns (uint256) {
        if (address(orderFees) == address(0)) return 0;
        return orderFees.flatFeeForOrder(token);
    }

    /// @notice Get percentage fee for an order
    /// @param value Value of order subject to percentage fee
    function getPercentageFeeForOrder(uint256 value) public view returns (uint256) {
        if (address(orderFees) == address(0)) return 0;
        return orderFees.percentageFeeForValue(value);
    }

    /// @inheritdoc OrderProcessor
    function _requestOrderAccounting(OrderRequest calldata orderRequest, bytes32 orderId)
        internal
        virtual
        override
        returns (Order memory order)
    {
        // Accumulate initial flat fee
        uint256 flatFee = getFlatFeeForOrder(orderRequest.paymentToken);
        _feesEarned[orderId] = flatFee;

        order = Order({
            recipient: orderRequest.recipient,
            assetToken: orderRequest.assetToken,
            paymentToken: orderRequest.paymentToken,
            sell: true,
            orderType: OrderType.MARKET,
            assetTokenQuantity: orderRequest.quantityIn,
            paymentTokenQuantity: 0,
            price: 0,
            tif: TIF.GTC,
            fee: 0
        });

        // Escrow
        IERC20(orderRequest.assetToken).safeTransferFrom(msg.sender, address(this), orderRequest.quantityIn);
    }

    /// @inheritdoc OrderProcessor
    function _fillOrderAccounting(
        OrderRequest calldata orderRequest,
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
        if (remainingOrder == 0) {
            delete _feesEarned[orderId];
        } else {
            // Collect fees
            if (collection > 0) {
                _feesEarned[orderId] = feesEarned;
            }
        }

        // Burn asset
        IMintBurn(orderRequest.assetToken).burn(fillAmount);
        // Move money
        IERC20(orderRequest.paymentToken).safeTransferFrom(msg.sender, address(this), receivedAmount);
        // Distribute
        if (remainingOrder == 0) {
            _distributeProceeds(
                orderRequest.paymentToken, orderRequest.recipient, orderState.received + receivedAmount, feesEarned
            );
        }
    }

    /// @inheritdoc OrderProcessor
    function _cancelOrderAccounting(OrderRequest calldata orderRequest, bytes32 orderId, OrderState memory orderState)
        internal
        virtual
        override
    {
        // if no fills, then full refund
        uint256 refund;
        if (orderState.remainingOrder == orderRequest.quantityIn) {
            refund = orderRequest.quantityIn;
        } else {
            _distributeProceeds(
                orderRequest.paymentToken, orderRequest.recipient, orderState.received, _feesEarned[orderId]
            );
            refund = orderState.remainingOrder;
        }
        delete _feesEarned[orderId];

        // Return Escrow
        IERC20(orderRequest.assetToken).safeTransfer(orderRequest.recipient, refund);
    }

    /// @dev Distribute proceeds to recipient and treasury
    function _distributeProceeds(address paymentToken, address recipient, uint256 totalReceived, uint256 feesEarned)
        private
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
