// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {BuyOrderIssuer} from "./BuyOrderIssuer.sol";
import "prb-math/Common.sol" as PrbMath;

/**
 * @title LimitBuyIssuer
 * @notice Extends BuyOrderIssuer to enable buy orders with a maximum acceptable price.
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/issuer/LimitBuyIssuer.sol)
 */
contract LimitBuyIssuer is BuyOrderIssuer {
    error LimitPriceNotSet();
    error OrderFillBelowLimitPrice();

    function _requestOrderAccounting(
        bytes32 id,
        OrderRequest calldata orderRequest,
        uint256 flatFee,
        uint64 percentageFeeRate
    ) internal virtual override returns (OrderConfig memory orderConfig) {
        // Calls the original _requestOrderAccounting from BuyOrderIssuer
        orderConfig = super._requestOrderAccounting(id, orderRequest, flatFee, percentageFeeRate);
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
    ) internal virtual override returns (uint256 paymentEarned, uint256 feesEarned) {
        // Ensure that the received amount is greater or equal to limit price * fill amount , orderRequest price has ether decimals
        if (fillAmount > PrbMath.mulDiv18(receivedAmount, order.price)) revert OrderFillBelowLimitPrice();

        (paymentEarned, feesEarned) = super._fillOrderAccounting(id, order, orderState, fillAmount, receivedAmount);
    }
}
