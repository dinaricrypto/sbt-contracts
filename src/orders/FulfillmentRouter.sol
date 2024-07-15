// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {AccessControlDefaultAdminRules} from
    "openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {IVault} from "./IVault.sol";
import {IOrderProcessor} from "./IOrderProcessor.sol";

/// @notice Specialized multicall for fulfilling orders with vault funds.
/// @dev Uses vault to remove the need for operator wallets to hold (non-gas) funds.
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/orders/FulfillmentRouter.sol)
contract FulfillmentRouter is AccessControlDefaultAdminRules, Multicall {
    using SafeERC20 for IERC20;

    error BuyFillsNotSupported();
    error OnlyForBuyOrders();

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    constructor(address initialOwner) AccessControlDefaultAdminRules(0, initialOwner) {}

    function fillOrder(
        address orderProcessor,
        address vault,
        IOrderProcessor.Order calldata order,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256 fees
    ) external onlyRole(OPERATOR_ROLE) {
        if (!order.sell) revert BuyFillsNotSupported();

        // withdraw payment token from vault
        IVault(vault).withdrawFunds(IERC20(order.paymentToken), address(this), receivedAmount);
        // fill order with payment token
        IERC20(order.paymentToken).safeIncreaseAllowance(orderProcessor, receivedAmount);
        IOrderProcessor(orderProcessor).fillOrder(order, fillAmount, receivedAmount, fees);
    }

    function cancelBuyOrder(
        address orderProcessor,
        IOrderProcessor.Order calldata order,
        address vault,
        uint256 orderId,
        string calldata reason
    ) external onlyRole(OPERATOR_ROLE) {
        if (order.sell) revert OnlyForBuyOrders();
        // get unfilledAmount
        uint256 unfilledAmount = IOrderProcessor(orderProcessor).getUnfilledAmount(orderId);

        if (unfilledAmount > 0) {
            // withdraw payment token from vault
            IVault(vault).withdrawFunds(IERC20(order.paymentToken), address(this), unfilledAmount);
            IERC20(order.paymentToken).safeIncreaseAllowance(orderProcessor, unfilledAmount);
            IOrderProcessor(orderProcessor).cancelOrder(order, reason);
        }
    }
}
