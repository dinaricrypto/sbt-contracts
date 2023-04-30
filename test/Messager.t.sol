// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Messager.sol";

contract MessagerTest is Test {
    event MessageSent(address indexed from, address indexed to, string message);

    Messager public messager;

    function setUp() public {
        messager = new Messager();
    }

    function testSendMessage(uint256 fromPrivateKey, address to, string calldata message) public {
        vm.assume(fromPrivateKey > 0);
        vm.assume(fromPrivateKey < 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(fromPrivateKey, messager.hashMessage(message));
        address from = vm.addr(fromPrivateKey);
        vm.expectEmit(true, true, true, true);
        emit MessageSent(from, to, message);
        messager.sendMessage(from, to, message, v, r, s);
    }

    function testSendMessageInvalidReverts() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, messager.hashMessage("one"));
        vm.expectRevert(Messager.InvalidSignature.selector);
        messager.sendMessage(vm.addr(1), address(3), "two", v, r, s);
    }
}
