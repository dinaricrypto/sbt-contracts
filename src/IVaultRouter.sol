// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "./IVault.sol";

/// @title IVaultRouter Interface
/// @notice Interface for the VaultRouter contract
/// @dev Provides functions for interacting with the Vault contract through the router
interface IVaultRouter {
    /// @notice Updates the address of the Vault contract
    /// @dev This function can only be called by authorized entities, typically the admin of the router
    /// @param _vault The new Vault contract address
    function updateVaultAddress(IVault _vault) external;

    /// @notice Withdraws funds from the Vault
    /// @dev This function is intended to be used for routing withdrawal requests to the Vault
    /// @param token The ERC20 token to be withdrawn
    /// @param user The address of the user to receive the withdrawn funds
    /// @param amount The amount of tokens to withdraw
    function withdrawFunds(IERC20 token, address user, uint256 amount) external;

    /// @notice Returns the current Vault address
    /// @return The address of the Vault contract
    function vault() external view returns (IVault);
}
