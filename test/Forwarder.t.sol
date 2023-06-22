// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Forwarder} from "../src/metatx/Forwarder.sol";

contract ForwarderTest is Test {
    Forwarder forwarder;
    address public relayer = address(0x1);

    function setUp() public {
        forwarder = new Forwarder(relayer, 30 seconds);
    }

    function test_addProcessor() public {
        forwarder.addProcessor(address(this));
        assertTrue(forwarder.validProcessors(address(this)));
    }

    function test_removeProcessor() public {
        forwarder.addProcessor(address(this));
        forwarder.removeProcessor(address(this));
        assertFalse(forwarder.validProcessors(address(this)));
    }

    function test_onlyRelayer() public {
        forwarder.addProcessor(address(this));
        forwarder.removeProcessor(address(this));
        assertFalse(forwarder.validProcessors(address(this)));
    }
}
