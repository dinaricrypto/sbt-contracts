// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";

abstract contract ControlledUpgradeable is UUPSUpgradeable, AccessControlDefaultAdminRulesUpgradeable {
    /// ------------------ Constants ------------------ ///
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// ------------------ Modifiers ------------------ ///

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    /// ------------------ Initialization ------------------ ///
    // slither-disable-next-line naming-convention
    function __ControlledUpgradeable_init(address initialOwner, address upgrader) internal {
        __AccessControlDefaultAdminRules_init_unchained(0, initialOwner);
        _grantRole(UPGRADER_ROLE, upgrader);
    }

    function version() public virtual returns (uint8);

    function publicVersion() public virtual returns (string memory);
}
