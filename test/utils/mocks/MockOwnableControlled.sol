// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {ControlledUpgradeable} from "../../../src/deployment/ControlledUpgradeable.sol";

contract MockOwnableControlled is ControlledUpgradeable {
    uint256 private _value;

    function initialize(address initialOwner) public reinitializer(version()) {
        __AccessControlDefaultAdminRules_init_unchained(0, initialOwner);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function reinitialize(address initialOwner, address upgrader) external reinitializer(version()) {
        __ControlledUpgradeable_init(initialOwner, upgrader);
    }

    function version() public pure override returns (uint8) {
        return 2;
    }

    function publicVersion() public pure override returns (string memory) {
        return "1.0.1";
    }
}
