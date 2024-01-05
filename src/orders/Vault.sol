// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {IVault} from "./IVault.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControlDefaultAdminRules} from
    "openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

/// @title Vault Contract
/// @notice This contract is used for managing and executing withdrawals of ERC20 tokens.
/// @dev Inherits from IVault and AccessControlDefaultAdminRules for role-based access control.
contract Vault is IVault, AccessControlDefaultAdminRules {
    using SafeERC20 for IERC20;

    event FundsWithdrawn(IERC20 token, address user, uint256 amount);

    /// @notice Role identifier for an authorized router
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Constructor to initialize the Vault with an admin
    /// @param admin Address of the default admin
    constructor(address admin) AccessControlDefaultAdminRules(0, admin) {}

    /// @notice Allows rescuing of ERC20 tokens locked in this contract.
    /// @dev Can only be called by an account with the DEFAULT_ADMIN_ROLE.
    /// @param token ERC20 token contract address to be rescued
    /// @param to Recipient address for the rescued tokens
    /// @param amount Amount of tokens to be rescued
    function rescueERC20(IERC20 token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        token.safeTransfer(to, amount);
    }

    /// @notice Withdraws funds from the vault to a specified user.
    /// @dev Can only be called by an account with the OPERATOR_ROLE.
    /// @param token ERC20 token to be withdrawn
    /// @param user User address to receive the withdrawn funds
    /// @param amount Amount of tokens to withdraw
    function withdrawFunds(IERC20 token, address user, uint256 amount) external override onlyRole(OPERATOR_ROLE) {
        emit FundsWithdrawn(token, user, amount);
        token.safeTransfer(user, amount);
    }
}
