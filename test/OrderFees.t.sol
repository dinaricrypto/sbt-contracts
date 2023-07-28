// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import "../src/issuer/OrderFees.sol";

contract OrderFeesTest is Test {
    event FeeSet(uint24 perOrderFee, uint24 percentageFee);

    OrderFees orderFees;
    MockERC20 usdc;

    function setUp() public {
        orderFees = new OrderFees(address(this), 10_000, 50);
        usdc = new MockERC20("USD Coin", "USDC", 6);
    }

    function decimalAdjust(uint8 decimals, uint256 fee) internal pure returns (uint256) {
        uint256 adjFee = fee;
        if (decimals < 18) {
            adjFee /= 10 ** (18 - decimals);
        } else if (decimals > 18) {
            adjFee *= 10 ** (decimals - 18);
        }
        return adjFee;
    }

    function testSetFee(uint24 perOrderFee, uint24 percentageFee, uint8 tokenDecimals, uint256 value) public {
        if (percentageFee >= 10000) {
            vm.expectRevert(OrderFees.FeeTooLarge.selector);
            orderFees.setFees(perOrderFee, percentageFee);
        } else {
            vm.expectEmit(true, true, true, true);
            emit FeeSet(perOrderFee, percentageFee);
            orderFees.setFees(perOrderFee, percentageFee);
            assertEq(orderFees.perOrderFee(), perOrderFee);
            assertEq(orderFees.percentageFeeRate(), percentageFee);
            assertEq(orderFees.percentageFeeForValue(value), PrbMath.mulDiv(value, percentageFee, 10000));
            MockERC20 newToken = new MockERC20("Test Token", "TEST", tokenDecimals);
            if (tokenDecimals > 18) {
                vm.expectRevert(OrderFees.DecimalsTooLarge.selector);
                orderFees.flatFeeForOrder(address(newToken));
            } else {
                assertEq(orderFees.flatFeeForOrder(address(newToken)), decimalAdjust(newToken.decimals(), perOrderFee));
            }
        }
    }

    function testUSDC() public {
        // 1 USDC flat fee
        uint256 flatFee = orderFees.flatFeeForOrder(address(usdc));
        console.log(flatFee);
        assertEq(flatFee, 1e6);
    }

    function testRecoverInputValueFromRemaining(uint24 percentageFeeRate, uint128 remainingValue) public {
        // uint128 used to avoid overflow when calculating larger raw input value
        vm.assume(percentageFeeRate < 10000);
        orderFees.setFees(orderFees.perOrderFee(), percentageFeeRate);

        uint256 inputValue = orderFees.recoverInputValueFromRemaining(remainingValue);
        uint256 percentageFee = orderFees.percentageFeeForValue(inputValue);
        assertEq(remainingValue, inputValue - percentageFee);
    }
}
