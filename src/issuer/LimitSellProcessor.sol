// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {SellOrderProcessor} from "./SellOrderProcessor.sol";
import "prb-math/Common.sol" as PrbMath;
import {IOrderFees} from "./IOrderFees.sol";

/**
 * @title LimitSellProcessor
 * @notice Extends SellOrderProcessor to enable sell orders with a minimum acceptable price.
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/issuer/LimitSellProcessor.sol)
 */
contract LimitSellProcessor is SellOrderProcessor {
    error LimitPriceNotSet();
    error OrderFillAboveLimitPrice();

    constructor(address _owner, address treasury_, IOrderFees orderFees_)
        SellOrderProcessor(_owner, treasury_, orderFees_)
    {}

    function _requestOrderAccounting(Order calldata order, bytes32 orderId) internal virtual override {
        // Calls the original _requestOrderAccounting from SellOrderProcessor
        super._requestOrderAccounting(order, orderId);
        // Ensure order type is LIMIT
        if (order.orderType != OrderType.LIMIT) revert OrderTypeMismatch();
        // Ensure that price is set for limit orders
        if (order.price == 0) revert LimitPriceNotSet();
    }

    function _fillOrderAccounting(
        Order calldata order,
        bytes32 orderId,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount
    ) internal virtual override {
        // Ensure that the received amount is greater or equal to limit price * fill amount, order price has ether decimals
        if (receivedAmount < PrbMath.mulDiv18(fillAmount, order.price)) revert OrderFillAboveLimitPrice();
        // Calls the original _fillOrderAccounting from SellOrderProcessor
        super._fillOrderAccounting(order, orderId, orderState, fillAmount, receivedAmount);
    }
}
