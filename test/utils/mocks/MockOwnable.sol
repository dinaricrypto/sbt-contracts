// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";

contract MockOwnableUpgradeable is UUPSUpgradeable, Ownable2StepUpgradeable {
    function initialize(address initialOwner) public initializer {
        __Ownable_init_unchained(initialOwner);
    }

    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
