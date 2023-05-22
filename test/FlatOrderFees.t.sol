// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solady/auth/Ownable.sol";
import "../src/FlatOrderFees.sol";

contract FlatOrderFeesTest is Test {
    event FeeSet(uint64 fee);

    FlatOrderFees orderFees;

    function setUp() public {
        orderFees = new FlatOrderFees(address(this), 0.005 ether);
    }

    function testInit(address token, bool sell, uint64 value) public {
        if (value == 0) {
            assertEq(orderFees.getFees(token, sell, value), 0);
        } else {
            assertEq(orderFees.getFees(token, sell, value), PrbMath.mulDiv18(value, 0.005 ether));
        }
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
