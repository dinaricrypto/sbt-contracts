// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import "../src/orders/OrderFees.sol";
import {FeeLib} from "../src/FeeLib.sol";

contract OrderFeesTest is Test {
    error DecimalsTooLarge();

    event FeeSet(uint64 perOrderFee, uint24 percentageFee);

    OrderFees orderFees;
    MockERC20 usdc;

    function setUp() public {
        orderFees = new OrderFees(address(this), 1 ether, 5_000);
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

    function testSetFee(uint64 perOrderFee, uint24 percentageFee, uint8 tokenDecimals, uint256 value) public {
        if (percentageFee >= 1_000_000) {
            vm.expectRevert(FeeLib.FeeTooLarge.selector);
            orderFees.setFees(perOrderFee, percentageFee);
        } else {
            vm.expectEmit(true, true, true, true);
            emit FeeSet(perOrderFee, percentageFee);
            orderFees.setFees(perOrderFee, percentageFee);
            assertEq(orderFees.perOrderFee(), perOrderFee);
            assertEq(orderFees.percentageFeeRate(), percentageFee);
            assertEq(
                FeeLib.percentageFeeForValue(value, orderFees.percentageFeeRate()),
                PrbMath.mulDiv(value, percentageFee, 1_000_000)
            );
            MockERC20 newToken = new MockERC20("Test Token", "TEST", tokenDecimals);
            if (tokenDecimals > 18) {
                vm.expectRevert(FeeLib.DecimalsTooLarge.selector);
                this.wrapPure(address(newToken));
            } else {
                assertEq(this.wrapPure(address(newToken)), decimalAdjust(newToken.decimals(), perOrderFee));
            }
        }
    }

    function testUSDC() public {
        // 1 USDC flat fee
        uint256 flatFee = FeeLib.flatFeeForOrder(address(usdc), orderFees.perOrderFee());
        assertEq(flatFee, 1e6);
    }

    function testRecoverInputValueFromRemaining(uint24 percentageFeeRate, uint128 remainingValue) public {
        // uint128 used to avoid overflow when calculating larger raw input value
        vm.assume(percentageFeeRate < 1_000_000);
        orderFees.setFees(orderFees.perOrderFee(), percentageFeeRate);

        uint256 inputValue = FeeLib.recoverInputValueFromRemaining(remainingValue, orderFees.percentageFeeRate());
        uint256 percentageFee = FeeLib.percentageFeeForValue(inputValue, orderFees.percentageFeeRate());
        assertEq(remainingValue, inputValue - percentageFee);
    }

    function wrapPure(address newToken) public view returns (uint256) {
        return FeeLib.flatFeeForOrder(newToken, orderFees.perOrderFee());
    }
}
