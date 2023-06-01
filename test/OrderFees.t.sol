// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solady/auth/Ownable.sol";
import "../src/OrderFees.sol";

contract OrderFeesTest is Test {
    event FeeSet(uint64 perOrderFee, uint64 percentageFee);

    OrderFees orderFees;

    function setUp() public {
        orderFees = new OrderFees(address(this), 1 ether, 0.005 ether);
    }

    function testInit(address token, bool sell, uint128 value) public {
        assertEq(orderFees.feesForOrder(token, sell, value), 1 ether + PrbMath.mulDiv18(value, 0.005 ether));
    }

    function testSetFee(uint64 perOrderFee, uint64 percentageFee, address token, bool sell, uint128 value) public {
        if (percentageFee > 1 ether) {
            vm.expectRevert(OrderFees.FeeTooLarge.selector);
            orderFees.setFees(perOrderFee, percentageFee);
        } else {
            vm.expectEmit(true, true, true, true);
            emit FeeSet(perOrderFee, percentageFee);
            orderFees.setFees(perOrderFee, percentageFee);
            assertEq(orderFees.perOrderFee(), perOrderFee);
            assertEq(orderFees.percentageFee(), percentageFee);
            assertEq(
                orderFees.feesForOrder(token, sell, value),
                uint256(perOrderFee) + PrbMath.mulDiv18(value, percentageFee)
            );
        }
    }
}
