// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import {MockxERC4626} from "./utils/mocks/MockxERC4626.sol";

contract xERC4626Test is Test {
    MockxERC4626 xToken;
    MockERC20 token;

    function setUp() public {
        token = new MockERC20("token", "TKN", 18);
        xToken = new MockxERC4626(token, 1000);
        token.mint(address(this), 100e18);
        token.approve(address(xToken), 100e18);
    }

    function testMetadata() public {
        assertEq(xToken.name(), "xtoken");
        assertEq(xToken.symbol(), "TKN.x");
        assertEq(xToken.decimals(), 18);
        assertEq(xToken.asset(), address(token));
    }

    function testTotalAssetsDuringRewardDistribution() public {
        // first seed pool with 50 tokens
        xToken.deposit(50e18, address(this));
        assertEq(xToken.totalAssets(), 50e18, "seed");

        // mint another 100 tokens
        token.mint(address(xToken), 100e18);
        assertEq(xToken.lastRewardAmount(), 0, "reward");
        assertEq(xToken.totalAssets(), 50e18, "totalassets");
        assertEq(xToken.convertToShares(50e18), 50e18); // 1:1 still

        xToken.syncRewards();
        // after sync, everything same except lastRewardAmount
        assertEq(xToken.lastRewardAmount(), 100e18);
        assertEq(xToken.totalAssets(), 50e18);
        assertEq(xToken.convertToShares(50e18), 50e18); // 1:1 still

        // accrue reward
        vm.warp(500);
        assertEq(xToken.lastRewardAmount(), 100e18);
        assertGt(xToken.totalAssets(), 50e18);
        assertLt(xToken.totalAssets(), 100e18);
        assertGt(xToken.convertToShares(100e18), 50e18);
    }

    function testWithdraw(uint256 amount) public {
        vm.assume(amount < 100e18);
        if (amount == 0) amount = 1;
        uint256 shareAmount = xToken.deposit(amount, address(this));
        assertEq(xToken.totalAssets(), amount, "seed");

        assertEq(shareAmount, amount);
        assertEq(xToken.previewWithdraw(shareAmount), amount);
        assertEq(xToken.totalSupply(), shareAmount);
        assertEq(xToken.totalAssets(), amount);

        assertEq(xToken.balanceOf(address(this)), shareAmount);
        assertEq(xToken.convertToAssets(xToken.balanceOf(address(this))), amount);

        assertEq(token.balanceOf(address(this)), 100e18 - amount);

        xToken.withdraw(amount, address(this), address(this));
        assertEq(xToken.balanceOf(address(this)), 0);
        assertEq(xToken.convertToAssets(xToken.balanceOf(address(this))), 0);
        assertEq(token.balanceOf(address(this)), 100e18);
    }
}
