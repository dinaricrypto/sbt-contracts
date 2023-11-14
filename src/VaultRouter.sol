// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IVaultRouter, IVault} from "./IVaultRouter.sol";
import {
    AccessControlDefaultAdminRules,
    AccessControl,
    IAccessControl
} from "openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

/// @title VaultRouter Contract
/// @notice This contract acts as a router to interact with the Vault for fund withdrawals and deposits.
contract VaultRouter is IVaultRouter, AccessControlDefaultAdminRules {
    using SafeERC20 for IERC20;

    IVault public vault;

    bytes32 public constant AUTHORIZED_PROCESSOR_ROLE = keccak256("AUTHORIZED_PROCESSOR_ROLE");

    /// @notice Constructor that sets the initial vault address and the contract owner.
    /// @param _vault The initial address of the Vault contract.
    constructor(IVault _vault) AccessControlDefaultAdminRules(0, msg.sender) {
        vault = _vault;
    }

    /// @notice Updates the address of the Vault contract.
    /// @dev This function can only be called by the owner of the contract.
    /// @param _vault The new address of the Vault contract.
    function updateVaultAddress(IVault _vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        vault = _vault;
    }

    /// @notice Withdraws funds from the Vault to a specified user address.
    /// @dev This function can only be called by the owner of the contract.
    /// @param token The ERC20 token to be withdrawn from the Vault.
    /// @param user The address where the withdrawn funds will be sent.
    /// @param amount The amount of tokens to withdraw.
    function withdrawFunds(IERC20 token, address user, uint256 amount) external onlyRole(AUTHORIZED_PROCESSOR_ROLE) {
        vault.withdrawFunds(token, user, amount);
    }
}
