// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {IVault} from "./IVault.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {ControlledUpgradeable} from "../deployment/ControlledUpgradeable.sol";

/// @title Vault Contract
/// @notice This contract is used for managing and executing withdrawals of ERC20 tokens
/// @dev Inherits from IVault and AccessControlDefaultAdminRules for role-based access control
contract Vault is IVault, ControlledUpgradeable {
    using SafeERC20 for IERC20;

    event FundsWithdrawn(IERC20 token, address user, uint256 amount);

    /// @notice Role identifier for an authorized router
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    ///--------------------- VERSION ---------------------///

    /// @notice Returns contract version as uint8
    /// @return Version number
    function version() public view override returns (uint8) {
        return 1;
    }

    /// @notice Returns contract version as string
    /// @return Version string
    function publicVersion() public view override returns (string memory) {
        return "1.0.0";
    }

    ///--------------------- INITIALIZATION ---------------------///

    /// @notice Initialize the vault with admin and upgrader
    /// @param admin Address of the admin
    /// @param upgrader Address authorized to upgrade contract
    function initialize(address admin, address upgrader) public reinitializer(version()) {
        __ControlledUpgradeable_init(admin, upgrader);
    }

    /// @notice Reinitialize the vault with a new upgrader
    /// @param upgrader Address authorized to upgrade contract
    function reinitialize(address upgrader) public reinitializer(version()) {
        grantRole(UPGRADER_ROLE, upgrader);
    }

    ///--------------------- CORE FUNCTIONS ---------------------///

    /// @notice Allows rescuing of ERC20 tokens locked in this contract
    /// @param token ERC20 token contract address to be rescued
    /// @param to Recipient address for the rescued tokens
    /// @param amount Amount of tokens to be rescued
    function rescueERC20(IERC20 token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        token.safeTransfer(to, amount);
    }

    /// @notice Withdraws funds from the vault to a specified user
    /// @param token ERC20 token to be withdrawn
    /// @param user User address to receive the withdrawn funds
    /// @param amount Amount of tokens to withdraw
    function withdrawFunds(IERC20 token, address user, uint256 amount) external override onlyRole(OPERATOR_ROLE) {
        emit FundsWithdrawn(token, user, amount);
        token.safeTransfer(user, amount);
    }
}
