// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import {FeeLib} from "../src/common/FeeLib.sol";

contract FeeLibTest is Test {
    MockERC20 usdc;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
    }

    function testUSDCFlatFee() public {
        // 1 USDC flat fee
        uint256 flatFee = wrapFlatFeeForOrder(usdc.decimals(), 1e8);
        assertEq(flatFee, 1e6);
    }

    function wrapFlatFeeForOrder(uint8 newTokenDecimals, uint64 perOrderFee) public pure returns (uint256) {
        return FeeLib.flatFeeForOrder(newTokenDecimals, perOrderFee);
    }
}
