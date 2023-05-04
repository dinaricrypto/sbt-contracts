// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solady/auth/Ownable.sol";
import "../src/FlatOrderFees.sol";

contract FlatOrderFeesTest is Test {
    event SellerFeeSet(uint64 fee);
    event BuyerFeeSet(uint64 fee);

    FlatOrderFees orderFees;

    function setUp() public {
        orderFees = new FlatOrderFees();
    }

    function testInit(bool sell, uint64 value) public {
        assertEq(orderFees.getFees(sell, value), 0);
    }

    function testSetSellerFee(uint64 fee) public {
        if (fee > 1 ether) {
            vm.expectRevert(FlatOrderFees.FeeTooLarge.selector);
            orderFees.setSellerFee(fee);
        } else {
            vm.expectEmit(true, true, true, true);
            emit SellerFeeSet(fee);
            orderFees.setSellerFee(fee);
            assertEq(orderFees.sellerFee(), fee);
        }
    }

    function testSetBuyerFee(uint64 fee) public {
        if (fee > 1 ether) {
            vm.expectRevert(FlatOrderFees.FeeTooLarge.selector);
            orderFees.setBuyerFee(fee);
        } else {
            vm.expectEmit(true, true, true, true);
            emit BuyerFeeSet(fee);
            orderFees.setBuyerFee(fee);
            assertEq(orderFees.buyerFee(), fee);
        }
    }
}
