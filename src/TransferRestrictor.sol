// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {ITransferRestrictor} from "./ITransferRestrictor.sol";
import {ControlledUpgradeable} from "./deployment/ControlledUpgradeable.sol";
/// @notice Enforces transfer restrictions
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/TransferRestrictor.sol)
/// Maintains the `RESTRICTOR_ROLE` who can add or remove accounts from `isBlacklisted`
/// Accounts may be restricted if they are suspected of malicious or illegal activity

contract TransferRestrictor is ControlledUpgradeable, ITransferRestrictor {
    /// ------------------ Types ------------------ ///

    /// @dev Account is restricted
    error AccountRestricted();

    /// @dev Emitted when `account` is added to `isBlacklisted`
    event Restricted(address indexed account);
    /// @dev Emitted when `account` is removed from `isBlacklisted`
    event Unrestricted(address indexed account);

    /// ------------------ Constants ------------------ ///

    /// @notice Role for approved compliance administrators
    bytes32 public constant RESTRICTOR_ROLE = keccak256("RESTRICTOR_ROLE");

    /// ------------------ State ------------------ ///

    /// @notice Accounts in `isBlacklisted` cannot send or receive tokens
    mapping(address => bool) public isBlacklisted;

    /// ----------------- Version ----------------- ///
    function version() public view override returns (uint8) {
        return 1;
    }

    function publicVersion() public view override returns (string memory) {
        return "1.0.0";
    }

    /// ------------------ Initialization ------------------ ///
    function initialize(address initialOwner, address upgrader) public reinitializer(version()) {
        __ControlledUpgradeable_init(initialOwner, upgrader);
    }

    function reinitialize(address upgrader) public reinitializer(version()) {
        grantRole(RESTRICTOR_ROLE, upgrader);
    }

    /// ------------------ Setters ------------------ ///

    /// @notice Restrict `account` from sending or receiving tokens
    /// @dev Does not check if `account` is restricted
    /// Can only be called by `RESTRICTOR_ROLE`
    function restrict(address account) external onlyRole(RESTRICTOR_ROLE) {
        isBlacklisted[account] = true;
        emit Restricted(account);
    }

    /// @notice Unrestrict `account` from sending or receiving tokens
    /// @dev Does not check if `account` is restricted
    /// Can only be called by `RESTRICTOR_ROLE`
    function unrestrict(address account) external onlyRole(RESTRICTOR_ROLE) {
        isBlacklisted[account] = false;
        emit Unrestricted(account);
    }

    /// ------------------ Transfer Restriction ------------------ ///

    /// @inheritdoc ITransferRestrictor
    function requireNotRestricted(address from, address to) external view virtual {
        // Check if either account is restricted
        if (isBlacklisted[from] || isBlacklisted[to]) {
            revert AccountRestricted();
        }
        // Otherwise, do nothing
    }
}
