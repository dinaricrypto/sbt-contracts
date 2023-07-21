// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ProofOfReserveAggregator} from "../src/proof-of-reserve/ProofOfReserveAggregator.sol";

contract ProofOfReserveAggregatorTest is Test {
    ProofOfReserveAggregator public aggregator;
    address private constant ASSET_1 = address(102);
    address private constant FEED_1 = address(103);
    address private constant FEED_2 = address(104);

    event ProofOfReserveFeedStateChanged(address indexed asset, address indexed proofOfReserveFeed, bool enabled);

    function setUp() public {
        vm.createSelectFork("arbitrum");
        aggregator = new ProofOfReserveAggregator();
    }

    function testProofOfReserveIsEnabled() public {
        address feed = aggregator.getProofOfReserveFeedForAsset(ASSET_1);
        assertEq(feed, address(0), "Proof of reserve feed should not be enabled");

        vm.expectEmit(true, true, true, true);
        emit ProofOfReserveFeedStateChanged(ASSET_1, FEED_1, true);
        aggregator.enableProofOfReserveFeed(ASSET_1, FEED_1);

        feed = aggregator.getProofOfReserveFeedForAsset(ASSET_1);
        assertEq(feed, FEED_1);
    }

    function testProofOfReserveFeedIsEnabledWhenAlreadyEnabled() public {
        aggregator.enableProofOfReserveFeed(ASSET_1, FEED_1);

        vm.expectRevert(ProofOfReserveAggregator.FeedAlreadyEnabled.selector);
        aggregator.enableProofOfReserveFeed(ASSET_1, FEED_2);

        address proofOfReserveFeed = aggregator.getProofOfReserveFeedForAsset(ASSET_1);
        assertEq(proofOfReserveFeed, FEED_1);
    }

    function testProofOfReserveFeedIsEnabledWithZeroPoRAddress() public {
        vm.expectRevert(ProofOfReserveAggregator.InvalidFeed.selector);
        aggregator.enableProofOfReserveFeed(ASSET_1, address(0));
    }

    function testProofOfReserveFeedIsEnabledWhenNotOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(address(0));
        aggregator.enableProofOfReserveFeed(ASSET_1, FEED_1);
    }

    function testProoOfReserveFeedIsDisabled() public {
        aggregator.enableProofOfReserveFeed(ASSET_1, FEED_1);
        address proofOfReserveFeed = aggregator.getProofOfReserveFeedForAsset(ASSET_1);
        assertEq(proofOfReserveFeed, FEED_1);

        vm.expectEmit(true, true, false, true);
        emit ProofOfReserveFeedStateChanged(ASSET_1, address(0), false);

        aggregator.disableProofOfReserveFeed(ASSET_1);
        proofOfReserveFeed = aggregator.getProofOfReserveFeedForAsset(ASSET_1);
        assertEq(proofOfReserveFeed, address(0));
    }

    function testProoOfReserveFeedIsDisabledWhenNotOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(address(0));
        aggregator.disableProofOfReserveFeed(ASSET_1);
    }

    function testAreAllReservesBackedEmptyArray() public {
        address[] memory assets = new address[](0);
        (bool areReservesBacked, bool[] memory unbackedAssetsFlags) = aggregator.areReservedBack(assets);

        assertEq(unbackedAssetsFlags.length, 0);
        assertEq(areReservesBacked, true);
    }
}
