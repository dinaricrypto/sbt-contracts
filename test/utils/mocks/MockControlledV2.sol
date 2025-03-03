// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {ControlledUpgradeable} from "../../../src/deployment/ControlledUpgradeable.sol";

contract MockControlledV2 is ControlledUpgradeable {
    uint256 public value;

    function initialize(address initialOwner, address upgrader) public reinitializer(version()) {
        __ControlledUpgradeable_init(initialOwner, upgrader);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function reinitialize(uint256 _value) external reinitializer(version()) {
        value = _value;
    }

    function version() public pure override returns (uint8) {
        return 3;
    }

    function publicVersion() public pure override returns (string memory) {
        return "1.0.2";
    }
}
