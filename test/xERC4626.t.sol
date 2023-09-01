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
        xToken = new MockxERC4626(token, "xToken", "xTKN", 1000);
        token.mint(address(this), 100e18);
        token.approve(address(xToken), 100e18);
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

        // // accrue remaining rewards
        // vm.warp(1000);
        // assertEq(xToken.lastRewardAmount() , 100e18);
        // assertEq(xToken.totalAssets() , 150e18);
        // assertEq(xToken.convertToShares(150e18) , 50e18); // 1:3 now

        // // accrue all and warp ahead 1 cycle
        // vm.warp(2000);
        // assertEq(xToken.lastRewardAmount() , 100e18);
        // assertEq(xToken.totalAssets() , 150e18);
        // assertEq(xToken.convertToShares(150e18) , 50e18); // 1:3 now
    }
}
