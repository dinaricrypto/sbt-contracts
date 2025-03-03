// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {ControlledUpgradeable} from "../../../src/deployment/ControlledUpgradeable.sol";

contract MockControlled is ControlledUpgradeable {
    function initialize(address initialOwner) public reinitializer(version()) {
        __ControlledUpgradeable_init(initialOwner, initialOwner);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function reinitialize(address upgrader) external reinitializer(version()) {
        _grantRole(UPGRADER_ROLE, upgrader);
    }

    function version() public pure override returns (uint8) {
        return 2;
    }

    function publicVersion() public pure override returns (string memory) {
        return "1.0.1";
    }
}
