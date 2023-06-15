// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import {OrderProcessor} from "./OrderProcessor.sol";
import {IMintBurn} from "../IMintBurn.sol";

/// @notice Contract managing market sell orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/issuer/SellOrderProcessor.sol)
contract SellOrderProcessor is OrderProcessor {
    using SafeERC20 for IERC20;

    /// ------------------ State ------------------ ///

    /// @dev orderId => feesEarned
    mapping(bytes32 => uint256) private _feesEarned;

    /// ------------------ Getters ------------------ ///

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
    function _requestOrderAccounting(OrderRequest calldata orderRequest, bytes32 orderId)
        internal
        virtual
        override
        returns (Order memory order)
    {
        // Accumulate initial flat fee
        uint256 flatFee = getFlatFeeForOrder(orderRequest.paymentToken);
        _feesEarned[orderId] = flatFee;

        // Construct order
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

        // Escrow asset for sale
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
        // Accumulate fees at each sill then take all at end
        uint256 collection = getPercentageFeeForOrder(receivedAmount);
        uint256 feesEarned = _feesEarned[orderId] + collection;
        // If order completely filled, clear fee data
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
        // Transfer raw proceeds of sale here
        IERC20(orderRequest.paymentToken).safeTransferFrom(msg.sender, address(this), receivedAmount);
        // Distribute if order completely filled
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
        // If no fills, then full refund
        uint256 refund;
        if (orderState.remainingOrder == orderRequest.quantityIn) {
            refund = orderRequest.quantityIn;
        } else {
            _distributeProceeds(
                orderRequest.paymentToken, orderRequest.recipient, orderState.received, _feesEarned[orderId]
            );
            refund = orderState.remainingOrder;
        }

        // Clear fee data
        delete _feesEarned[orderId];

        // Return escrow
        IERC20(orderRequest.assetToken).safeTransfer(orderRequest.recipient, refund);
    }

    /// @dev Distribute proceeds and fees
    function _distributeProceeds(address paymentToken, address recipient, uint256 totalReceived, uint256 feesEarned)
        private
    {
        // If fees larger than total received, then no proceeds to recipient
        uint256 proceeds = 0;
        uint256 collection = 0;
        if (totalReceived > feesEarned) {
            proceeds = totalReceived - feesEarned;
            collection = feesEarned;
        } else {
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
