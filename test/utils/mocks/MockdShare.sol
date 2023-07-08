// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {dShare} from "../../../src/dShare.sol";
import {TransferRestrictor} from "../../../src/TransferRestrictor.sol";

contract MockdShare is dShare {
    constructor() dShare(msg.sender, "Dinari Token", "dTKN", "example.com", new TransferRestrictor(msg.sender)) {}
}
