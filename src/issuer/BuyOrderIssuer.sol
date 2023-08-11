// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import {OrderProcessor, ITokenLockCheck} from "./OrderProcessor.sol";
import {IMintBurn} from "../IMintBurn.sol";
import {IOrderFees} from "./IOrderFees.sol";
import {FeeLib} from "../FeeLib.sol";

/// @notice Contract managing market purchase orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/BuyOrderIssuer.sol)
/// This order processor emits market orders to buy the underlying asset that are good until cancelled
/// Fees are calculated upfront and held back from the order amount
/// The payment is escrowed until the order is filled or cancelled
/// Payment is automatically refunded if the order is cancelled
/// Implicitly assumes that asset tokens are dShare and can be minted
contract BuyOrderIssuer is OrderProcessor {
    // Handle token transfers safely
    using SafeERC20 for IERC20;

    constructor(address _owner, address treasury_, IOrderFees orderFees_, ITokenLockCheck tokenLockCheck_)
        OrderProcessor(_owner, treasury_, orderFees_, tokenLockCheck_)
    {}

    /// ------------------ Fee Helpers ------------------ ///

    /// @notice Get the raw input value and fees that produce a final order value
    /// @param token Payment token for order
    /// @param orderValue Final order value
    /// @return inputValue Total input value subject to fees
    /// @return flatFee Flat fee for order
    /// @return percentageFee Percentage fee for order
    /// @dev Fees zero if no orderFees contract is set
    function getInputValueForOrderValue(address token, uint256 orderValue)
        external
        view
        returns (uint256 inputValue, uint256 flatFee, uint256 percentageFee)
    {
        // Check if fee contract is set
        if (address(orderFees) == address(0)) {
            return (orderValue, 0, 0);
        }

        // Calculate input value after flat fee
        uint256 recoveredValue = FeeLib.recoverInputValueFromRemaining(orderValue, orderFees.percentageFeeRate());
        // Calculate fees
        percentageFee = FeeLib.percentageFeeForValue(recoveredValue, orderFees.percentageFeeRate());
        flatFee = FeeLib.flatFeeForOrder(token, orderFees.perOrderFee());
        // Calculate raw input value
        inputValue = recoveredValue + flatFee;
    }

    /// ------------------ Order Lifecycle ------------------ ///

    /// @inheritdoc OrderProcessor
    function _requestOrderAccounting(bytes32, Order calldata order, uint256 totalFees) internal virtual override {
        // TODO: verify quantityIn

        // Escrow payment for purchase
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), order.paymentTokenQuantity + totalFees);
    }

    function _fillOrderAccounting(
        bytes32,
        Order calldata order,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256
    ) internal virtual override returns (uint256 paymentEarned, uint256 feesEarned) {
        paymentEarned = fillAmount;
        // Fees - earn the flat fee if first fill, then earn percentage fee on the fill
        // TODO: make sure that all fees are taken at total fill to prevent dust accumulating here
        feesEarned = 0;
        if (orderState.feesPaid == 0) {
            feesEarned = orderState.flatFee;
        }
        uint256 totalPercentageFees = order.quantityIn - order.paymentTokenQuantity - orderState.flatFee;
        feesEarned += PrbMath.mulDiv(totalPercentageFees, fillAmount, order.paymentTokenQuantity);
    }

    /// @inheritdoc OrderProcessor
    function _cancelOrderAccounting(bytes32, Order calldata order, OrderState memory orderState)
        internal
        virtual
        override
        returns (uint256 refund)
    {
        uint256 totalFees = order.quantityIn - order.paymentTokenQuantity;
        // If no fills, then full refund
        refund = orderState.remainingOrder + totalFees;
        if (refund < order.quantityIn) {
            // Refund remaining order and fees
            refund -= orderState.feesPaid;
        }
    }
}
