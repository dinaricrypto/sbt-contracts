// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {ProofOfReserveAggregator} from "../src/proof-of-reserve/ProofOfReserveAggregator.sol";
import {ProofOfReserveExecutor} from "../src/proof-of-reserve/ProofOfReserveExecutor.sol";

contract ProofOfReserveExecutorTest is Test {
    ProofOfReserveAggregator private aggregator;
    ProofOfReserveExecutor private executor;

    event AssetStateChanged(address indexed asset, bool enabled);

    address private constant ASSET_1 = address(1234);
    address private constant FEED_1 = address(4321);

    function setUp() public {
        aggregator = new ProofOfReserveAggregator();
        executor = new ProofOfReserveExecutor(address(aggregator));
    }

    function testAssetsAreEnabled() public {
        address[] memory enabledAssets = executor.getAssets();
        assertEq(enabledAssets.length, 0);

        address[] memory assets = new address[](1);
        assets[0] = ASSET_1;

        vm.expectEmit(true, false, false, true);
        emit AssetStateChanged(ASSET_1, true);
        executor.enableAssets(assets);

        enabledAssets = executor.getAssets();
        assertEq(enabledAssets.length, 1);
        assertEq(enabledAssets[0], ASSET_1);
    }
}
