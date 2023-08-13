// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {MarketBuyProcessor, ITokenLockCheck} from "./MarketBuyProcessor.sol";
import "prb-math/Common.sol" as PrbMath;
import {IOrderFees} from "./IOrderFees.sol";

/**
 * @title LimitBuyProcessor
 * @notice Extends MarketBuyProcessor to enable buy orders with a maximum acceptable price.
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/orders/LimitBuyProcessor.sol)
 */
contract LimitBuyProcessor is MarketBuyProcessor {
    error LimitPriceNotSet();
    error OrderFillBelowLimitPrice();

    constructor(address _owner, address treasury_, IOrderFees orderFees_, ITokenLockCheck tokenLockCheck_)
        MarketBuyProcessor(_owner, treasury_, orderFees_, tokenLockCheck_)
    {}

    function _requestOrderAccounting(bytes32 id, Order calldata order, uint256 totalFees) internal virtual override {
        // Calls the original _requestOrderAccounting from MarketBuyProcessor
        super._requestOrderAccounting(id, order, totalFees);
        // Ensure order type is LIMIT
        if (order.orderType != OrderType.LIMIT) revert OrderTypeMismatch();
        // Ensure that price is set for limit orders
        if (order.price == 0) revert LimitPriceNotSet();
    }

    function _fillOrderAccounting(
        bytes32 id,
        Order calldata order,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount
    ) internal virtual override returns (uint256 paymentEarned, uint256 feesEarned) {
        // Ensure that the received amount is greater or equal to fill amount / limit price , order price has ether decimals
        if (receivedAmount < PrbMath.mulDiv(fillAmount, 1 ether, order.price)) revert OrderFillBelowLimitPrice();

        (paymentEarned, feesEarned) = super._fillOrderAccounting(id, order, orderState, fillAmount, receivedAmount);
    }
}
