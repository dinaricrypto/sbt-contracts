// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title IVault Interface
/// @notice Interface for the Vault contract
/// @dev Interface of a Vault that allows for ERC20 token deposits and withdrawals
interface IVault {
    /// @notice Withdraws funds from the vault
    /// @dev This function should only be called by authorized entities
    /// @param token The ERC20 token to be withdrawn
    /// @param user The address of the user to receive the withdrawn funds
    /// @param amount The amount of tokens to withdraw
    function withdrawFunds(IERC20 token, address user, uint256 amount) external;
}
