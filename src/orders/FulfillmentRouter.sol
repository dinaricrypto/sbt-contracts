// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "./IVault.sol";
import {IOrderProcessor} from "./IOrderProcessor.sol";

/// @notice Specialized multicall for fulfilling orders with vault funds.
/// @dev Uses vault to remove the need for operator wallets to hold (non-gas) funds.
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/orders/FulfillmentRouter.sol)
contract FulfillmentRouter {
    using SafeERC20 for IERC20;

    error Unauthorized();

    // matches OrderProcessor.OPERATOR_ROLE
    bytes32 constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    function fillOrder(
        address orderProcessor,
        address vault,
        IOrderProcessor.Order calldata order,
        uint256 index,
        uint256 fillAmount,
        uint256 receivedAmount
    ) external {
        // passthrough role check
        if (!IAccessControl(orderProcessor).hasRole(OPERATOR_ROLE, msg.sender)) revert Unauthorized();

        if (order.sell) {
            // withdraw payment token from vault
            IVault(vault).withdrawFunds(IERC20(order.paymentToken), address(this), receivedAmount);
            // fill order with payment token
            IERC20(order.paymentToken).safeIncreaseAllowance(orderProcessor, receivedAmount);
            IOrderProcessor(orderProcessor).fillOrder(order, index, fillAmount, receivedAmount);
        } else {
            // fill order and receive payment token
            IOrderProcessor(orderProcessor).fillOrder(order, index, fillAmount, receivedAmount);
            // deposit payment token into vault
            IERC20(order.paymentToken).safeTransfer(vault, fillAmount);
        }
    }
}
