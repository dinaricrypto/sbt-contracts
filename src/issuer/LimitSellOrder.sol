// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SellOrderProcessor, OrderProcessor} from "./SellOrderProcessor.sol";
import {IMintBurn} from "../IMintBurn.sol";

contract LimitSellOrder is SellOrderProcessor {
    // Handle token transfers safely
    using SafeERC20 for IERC20;

    error LimitPriceNotSet();
    error OrderFillAboveLimitPrice();

    function _requestOrderAccounting(OrderRequest calldata orderRequest, bytes32 orderId)
        internal
        virtual
        override
        returns (Order memory order)
    {
        // Calls the original _requestOrderAccounting from SellOrderProcessor
        order = super._requestOrderAccounting(orderRequest, orderId);
        // Modify order type to LIMIT
        order.orderType = OrderType.LIMIT;
        // Ensure that price is set for limit orders
        if (orderRequest.price == 0) revert LimitPriceNotSet();
        // Set the price for the limit order
        order.price = orderRequest.price;
    }

    function _fillOrderAccounting(
        OrderRequest calldata orderRequest,
        bytes32 orderId,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount
    ) internal virtual override {
        // Ensure that the received amount is greater or equal to limit price * fill amount
        if (fillAmount * orderRequest.price < receivedAmount) revert OrderFillAboveLimitPrice();
        // Calls the original _fillOrderAccounting from SellOrderProcessor
        super._fillOrderAccounting(orderRequest, orderId, orderState, fillAmount, receivedAmount);
    }
}
