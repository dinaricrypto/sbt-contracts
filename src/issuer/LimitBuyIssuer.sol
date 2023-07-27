// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {BuyOrderIssuer} from "./BuyOrderIssuer.sol";
import "prb-math/Common.sol" as PrbMath;
import {IOrderFees} from "./IOrderFees.sol";

/**
 * @title LimitBuyIssuer
 * @notice Extends BuyOrderIssuer to enable buy orders with a maximum acceptable price.
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/issuer/LimitBuyIssuer.sol)
 */
contract LimitBuyIssuer is BuyOrderIssuer {
    error LimitPriceNotSet();
    error OrderFillBelowLimitPrice();

    constructor(address _owner, address treasury_, IOrderFees orderFees_)
        BuyOrderIssuer(_owner, treasury_, orderFees_)
    {}

    function _requestOrderAccounting(OrderRequest calldata orderRequest, bytes32 orderId)
        internal
        virtual
        override
        returns (Order memory order)
    {
        // Calls the original _requestOrderAccounting from BuyOrderIssuer
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
        // Ensure that the received amount is greater or equal to limit price * fill amount , orderRequest price has ether decimals
        if (fillAmount > PrbMath.mulDiv18(receivedAmount, orderRequest.price)) revert OrderFillBelowLimitPrice();
        // Calls the original _fillOrderAccounting from BuyOrderIssuer
        super._fillOrderAccounting(orderRequest, orderId, orderState, fillAmount, receivedAmount);
    }
}
