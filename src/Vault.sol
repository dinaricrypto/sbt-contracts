// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {IVault} from "./IVault.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    AccessControlDefaultAdminRules,
    AccessControl,
    IAccessControl
} from "openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

contract Vault is IVault, AccessControlDefaultAdminRules {
    using SafeERC20 for IERC20;

    bytes32 public constant SELL_PROCESSOR_ROLE = keccak256("SELL_PROCESSOR_ROLE");

    constructor() AccessControlDefaultAdminRules(0, msg.sender) {}

    /**
     * @notice Rescue ERC20 tokens locked up in this contract.
     * @param tokenContract ERC20 token contract address
     * @param to        Recipient address
     * @param amount    Amount to withdraw
     */
    function rescueERC20(IERC20 tokenContract, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        tokenContract.safeTransfer(to, amount);
    }

    function withdrawFunds(address token, address user, uint256 amount)
        external
        override
        onlyRole(SELL_PROCESSOR_ROLE)
    {
        IERC20(token).safeTransfer(user, amount);
    }
}
