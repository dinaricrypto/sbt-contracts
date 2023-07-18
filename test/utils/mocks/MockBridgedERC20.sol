// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BridgedERC20} from "../../../src/BridgedERC20.sol";
import {TransferRestrictor} from "../../../src/TransferRestrictor.sol";
import {BridgedERC20Factory} from "../../../src/BridgedERC20Factory.sol";

contract MockBridgedERC20 is BridgedERC20 {
    constructor()
        BridgedERC20(
            msg.sender,
            "Dinari Token",
            "dTKN",
            "example.com",
            new TransferRestrictor(msg.sender),
            0,
            false,
            address(new BridgedERC20Factory())
        )
    {}
}
