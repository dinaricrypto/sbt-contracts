// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {SellOrderProcessor} from "./SellOrderProcessor.sol";
import "prb-math/Common.sol" as PrbMath;

/**
 * @title LimitSellProcessor
 * @notice Extends SellOrderProcessor to enable sell orders with a minimum acceptable price.
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/issuer/LimitSellProcessor.sol)
 */
contract LimitSellProcessor is SellOrderProcessor {
    error LimitPriceNotSet();
    error OrderFillAboveLimitPrice();

    function _requestOrderAccounting(bytes32 id, OrderRequest calldata orderRequest)
        internal
        virtual
        override
        returns (OrderConfig memory orderConfig)
    {
        // Calls the original _requestOrderAccounting from SellOrderProcessor
        orderConfig = super._requestOrderAccounting(id, orderRequest);
        // Modify order type to LIMIT
        orderConfig.orderType = OrderType.LIMIT;
        // Ensure that price is set for limit orders
        if (orderRequest.price == 0) revert LimitPriceNotSet();
        // Set the price for the limit order
        orderConfig.price = orderRequest.price;
    }

    function _fillOrderAccounting(
        bytes32 id,
        Order calldata order,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount
    ) internal virtual override {
        // Ensure that the received amount is greater or equal to limit price * fill amount, orderRequest price has ether decimals
        if (receivedAmount < PrbMath.mulDiv18(fillAmount, order.price)) revert OrderFillAboveLimitPrice();
        // Calls the original _fillOrderAccounting from SellOrderProcessor
        super._fillOrderAccounting(id, order, orderState, fillAmount, receivedAmount);
    }
}
