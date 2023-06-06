// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solady-test/utils/mocks/MockERC20.sol";
import "solady/auth/Ownable.sol";
import "../src/issuer/OrderFees.sol";

contract OrderFeesTest is Test {
    event FeeSet(uint64 perOrderFee, uint64 percentageFee);

    OrderFees orderFees;
    MockERC20 token;
    MockERC20 usdc;

    function setUp() public {
        orderFees = new OrderFees(address(this), 1 ether, 0.005 ether);
        token = new MockERC20("Test Token", "TEST", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
    }

    function perOrderFeeAdjust(uint8 decimals, uint256 fee) internal pure returns (uint256) {
        uint256 adjFee = fee;
        if (decimals < 18) {
            adjFee /= 10 ** (18 - decimals);
        } else if (decimals > 18) {
            adjFee *= 10 ** (decimals - 18);
        }
        return adjFee;
    }

    // function testValueFromRemainingValue(uint256 remainingValue) public {
    //     // FIXME: make fee rounding correct
    //     uint256 inputValue = orderFees.recoverInputValueFromValue(remainingValue);
    //     uint256 percentageFee = orderFees.percentageFeeForValue(inputValue);
    //     assertEq(remainingValue + percentageFee, inputValue);
    //     uint256 percentageFeeOnRemaining = orderFees.percentageFeeOnRemainingValue(inputValue);
    //     assertEq(percentageFee, percentageFeeOnRemaining);
    // }

    // function testInit(uint8 tokenDecimals, bool sell, uint128 value) public {
    //     MockERC20 newToken = new MockERC20("Test Token", "TEST", tokenDecimals);
    //     if (tokenDecimals > 18) {
    //         vm.expectRevert(OrderFees.DecimalsTooLarge.selector);
    //         orderFees.feesForOrder(address(newToken), sell, value);
    //     } else {
    //         assertEq(orderFees.perOrderFee(), 1 ether);
    //         assertEq(orderFees.percentageFee(), 0.005 ether);
    //         assertEq(
    //             orderFees.feesForOrder(address(newToken), sell, value),
    //             perOrderFeeAdjust(tokenDecimals, 1 ether) + PrbMath.mulDiv18(value, 0.005 ether)
    //         );
    //     }
    // }

    // function testSetFee(uint64 perOrderFee, uint64 percentageFee, bool sell, uint128 value) public {
    //     if (percentageFee > 1 ether) {
    //         vm.expectRevert(OrderFees.FeeTooLarge.selector);
    //         orderFees.setFees(perOrderFee, percentageFee);
    //     } else {
    //         vm.expectEmit(true, true, true, true);
    //         emit FeeSet(perOrderFee, percentageFee);
    //         orderFees.setFees(perOrderFee, percentageFee);
    //         assertEq(orderFees.perOrderFee(), perOrderFee);
    //         assertEq(orderFees.percentageFee(), percentageFee);
    //         assertEq(
    //             orderFees.feesForOrder(address(token), sell, value),
    //             uint256(perOrderFee) + PrbMath.mulDiv18(value, percentageFee)
    //         );
    //     }
    // }

    function testUSDC() public {
        // 1 USDC flat fee
        uint256 flatFee = orderFees.flatFeeForOrder(address(usdc));
        assertEq(flatFee, 1e6);
    }
}
