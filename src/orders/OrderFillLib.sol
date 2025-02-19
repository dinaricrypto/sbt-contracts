// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {OrderCommonTypes} from "./types/OrderCommonTypes.sol";
import {OrderErrors} from "./OrderErrors.sol";
import {mulDiv, mulDiv18} from "prb-math/Common.sol";
import {OracleLib} from "../common/OracleLib.sol";
import {IDShare} from "../IDShare.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

library OrderFillLib {
    using SafeERC20 for IERC20;

    /// @dev Emitted for each fill
    event OrderFill(
        uint256 indexed id,
        address indexed paymentToken,
        address indexed assetToken,
        address requester,
        uint256 assetAmount,
        uint256 paymentAmount,
        uint256 feesTaken,
        bool sell
    );

    event OrderFulfilled(uint256 indexed id, address indexed requester);

    function processSellFill(
        OrderCommonTypes.OrderProcessorStorage storage $,
        uint256 id,
        OrderCommonTypes.Order calldata order,
        OrderCommonTypes.OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256 fees
    ) internal returns (bool fulfilled) {
        // Checks
        if (fees > receivedAmount) revert OrderErrors.AmountTooLarge();
        if (order.orderType == OrderCommonTypes.OrderType.LIMIT && receivedAmount < mulDiv18(fillAmount, order.price)) {
            revert OrderErrors.OrderFillAboveLimitPrice();
        }

        // Effects
        _updateLatestPrice($, order, fillAmount, receivedAmount);
        fulfilled = _updateFillState($, id, orderState, fillAmount, receivedAmount, fees);

        // Events
        emit OrderFill(
            id, order.paymentToken, order.assetToken, order.recipient, fillAmount, receivedAmount, fees, true
        );
        if (fulfilled) {
            emit OrderFulfilled(id, orderState.requester);
        }

        // Interactions
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), receivedAmount);

        uint256 paymentEarned = receivedAmount - fees;
        if (paymentEarned > 0) {
            IERC20(order.paymentToken).safeTransfer(order.recipient, paymentEarned);
        }

        return fulfilled;
    }

    function processBuyFill(
        OrderCommonTypes.OrderProcessorStorage storage $,
        uint256 id,
        OrderCommonTypes.Order calldata order,
        OrderCommonTypes.OrderState memory orderState,
        uint256 assetAmount,
        uint256 paymentAmount,
        uint256 fees
    ) internal returns (bool fulfilled) {
        // Checks
        if (fees > orderState.feesEscrowed) revert OrderErrors.AmountTooLarge();
        if (
            order.orderType == OrderCommonTypes.OrderType.LIMIT
                && assetAmount < mulDiv(paymentAmount, 1 ether, order.price)
        ) {
            revert OrderErrors.OrderFillBelowLimitPrice();
        }

        // Effects
        _updateLatestPrice($, order, assetAmount, paymentAmount);
        fulfilled = _updateFillState($, id, orderState, paymentAmount, assetAmount, fees);

        // Events
        emit OrderFill(
            id, order.paymentToken, order.assetToken, order.recipient, assetAmount, paymentAmount, fees, false
        );
        if (fulfilled) {
            emit OrderFulfilled(id, orderState.requester);
        }

        // Fee escrow update
        uint256 remainingFeesEscrowed = orderState.feesEscrowed - fees;
        if (fulfilled) {
            if (remainingFeesEscrowed > 0) {
                IERC20(order.paymentToken).safeTransfer(orderState.requester, remainingFeesEscrowed);
            }
        } else {
            $._orders[id].feesEscrowed = remainingFeesEscrowed;
        }

        // Interactions
        IDShare(order.assetToken).mint(order.recipient, assetAmount);

        return fulfilled;
    }

    function _updateLatestPrice(
        OrderCommonTypes.OrderProcessorStorage storage $,
        OrderCommonTypes.Order calldata order,
        uint256 assetAmount,
        uint256 paymentAmount
    ) private {
        bytes32 pairIndex = OracleLib.pairIndex(order.assetToken, order.paymentToken);
        $._latestFillPrice[pairIndex] = OrderCommonTypes.PricePoint({
            blocktime: uint64(block.timestamp),
            price: order.orderType == OrderCommonTypes.OrderType.LIMIT
                ? order.price
                : OracleLib.calculatePrice(assetAmount, paymentAmount, $._paymentTokens[order.paymentToken].decimals)
        });
    }

    function _updateFillState(
        OrderCommonTypes.OrderProcessorStorage storage $,
        uint256 id,
        OrderCommonTypes.OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256 fees
    ) private returns (bool fulfilled) {
        uint256 newUnfilledAmount = orderState.unfilledAmount - fillAmount;
        $._orders[id].unfilledAmount = newUnfilledAmount;
        $._orders[id].receivedAmount = orderState.receivedAmount + receivedAmount;
        $._orders[id].feesTaken = orderState.feesTaken + fees;

        fulfilled = newUnfilledAmount == 0;
        if (fulfilled) {
            $._orders[id].feesEscrowed = 0;
            $._status[id] = OrderCommonTypes.OrderStatus.FULFILLED;
        }
        return fulfilled;
    }
}
