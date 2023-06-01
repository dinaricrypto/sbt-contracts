// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BridgedERC20} from "../../../src/BridgedERC20.sol";
import {TransferRestrictor} from "../../../src/TransferRestrictor.sol";

contract MockBridgedERC20 is BridgedERC20 {
    constructor() BridgedERC20(msg.sender, "Dinari Token", "dTKN", "example.com", new TransferRestrictor(msg.sender)) {}
}
