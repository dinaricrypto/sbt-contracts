// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../src/BridgedERC20.sol";
import "../../src/TransferRestrictor.sol";

contract MockBridgedERC20 is BridgedERC20 {
    constructor() BridgedERC20("Dinari Token", "dTKN", "example.com", new TransferRestrictor()) {}
}
