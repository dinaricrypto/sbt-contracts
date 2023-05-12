// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solady/auth/Ownable.sol";
import "../src/FlatOrderFees.sol";

contract FlatOrderFeesTest is Test {
    event FeeSet(uint64 fee);

    FlatOrderFees orderFees;

    function setUp() public {
        orderFees = new FlatOrderFees();
    }

    function testInit(address token, bool sell, uint64 value) public {
        assertEq(orderFees.getFees(token, sell, value), 0);
    }

    function testSetFee(uint64 fee) public {
        if (fee > 1 ether) {
            vm.expectRevert(FlatOrderFees.FeeTooLarge.selector);
            orderFees.setFee(fee);
        } else {
            vm.expectEmit(true, true, true, true);
            emit FeeSet(fee);
            orderFees.setFee(fee);
            assertEq(orderFees.fee(), fee);
        }
    }
}
