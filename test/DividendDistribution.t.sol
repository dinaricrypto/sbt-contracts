// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";
import {DataHelper} from "./utils/DataHelper.sol";
import {Merkle} from "murky/Merkle.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

contract DividendDistributionTest is Test, DataHelper {
    Merkle merkle;

    DividendDistribution distribution;
    MockERC20 token;

    uint256 public userPrivateKey;
    uint256 public ownerPrivateKey;

    address public user;
    address public owner;

    bytes32[] data;
    bytes32 root;

    uint256[] public resultsArray;

    struct HashAndDataTuple {
        uint256 originalData;
        bytes32 hash;
    }

    event Distributed(uint256 indexed distributionId, address indexed account, uint256 amount);
    event NewDistributionCreated(
        uint256 indexed distributionId, uint256 totalDistribution, uint256 startDate, uint256 endDate
    );
    event DistributionReclaimed(uint256 indexed distributionId, uint256 totalReclaimed);

    function setUp() public {
        userPrivateKey = 0x1;
        ownerPrivateKey = 0x2;

        merkle = new Merkle();

        token = new MockERC20("Money", "$", 6);

        user = vm.addr(userPrivateKey);
        owner = vm.addr(ownerPrivateKey);
        vm.prank(owner);
        distribution = new DividendDistribution();

        // copmute merkle root for test data
        data = generateData(address(distribution));
        root = merkle.getRoot(data);
    }

    function testCreateNewDistribution(bytes32 _merkleRoot, uint256 _totalDistribution, uint256 _endTime) public {
        vm.assume(_totalDistribution < 1e8);
        assertEq(IERC20(address(token)).balanceOf(address(distribution)), 0);

        token.mint(owner, _totalDistribution);

        vm.prank(owner);
        token.approve(address(distribution), _totalDistribution);

        if (_endTime <= block.timestamp) {
            vm.expectRevert(DividendDistribution.EndTimeInPast.selector);
            vm.prank(owner);
            distribution.createDistribution(address(token), _merkleRoot, _totalDistribution, _endTime);
        } else {
            vm.expectEmit(true, true, true, true);
            emit NewDistributionCreated(0, _totalDistribution, block.timestamp, _endTime);
            vm.prank(owner);
            distribution.createDistribution(address(token), _merkleRoot, _totalDistribution, _endTime);
            assertEq(IERC20(address(token)).balanceOf(address(distribution)), _totalDistribution);
            assertEq(IERC20(address(token)).balanceOf(owner), 0);
        }
    }

    function testCreateDistributionNotOwnerReverts() public {
        uint256 _totalDistribution =
            DataHelper.distributionAmount0 + DataHelper.distributionAmount1 + DataHelper.distributionAmount2;

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user);
        distribution.createDistribution(address(token), root, _totalDistribution, block.timestamp + 1);
    }

    function testDistribute() public {
        uint256 _totalDistribution =
            DataHelper.distributionAmount0 + DataHelper.distributionAmount1 + DataHelper.distributionAmount2;

        // Generate proof for index 0 using the copy
        bytes32[] memory proofForIndex0 = merkle.getProof(data, 0);

        // Generate proof for index 1 using the copy
        bytes32[] memory proofForIndex1 = merkle.getProof(data, 1);

        token.mint(owner, _totalDistribution);

        vm.prank(owner);
        token.approve(address(distribution), _totalDistribution);
        vm.prank(owner);
        uint256 distributionId =
            distribution.createDistribution(address(token), root, _totalDistribution, block.timestamp + 1);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(DataHelper.distributionAddress0);
        distribution.distribute(
            distributionId, DataHelper.distributionAddress0, DataHelper.distributionAmount0, proofForIndex0
        );

        vm.expectEmit(true, true, true, true);
        emit Distributed(distributionId, DataHelper.distributionAddress0, DataHelper.distributionAmount0);
        vm.prank(owner);
        distribution.distribute(
            distributionId, DataHelper.distributionAddress0, DataHelper.distributionAmount0, proofForIndex0
        );
        assertEq(IERC20(address(token)).balanceOf(DataHelper.distributionAddress0), DataHelper.distributionAmount0);

        vm.expectRevert(DividendDistribution.AlreadyClaimed.selector);
        vm.prank(owner);
        distribution.distribute(
            distributionId, DataHelper.distributionAddress0, DataHelper.distributionAmount0, proofForIndex0
        );

        vm.expectRevert(DividendDistribution.InvalidProof.selector);
        vm.prank(owner);
        distribution.distribute(
            distributionId, DataHelper.distributionAddress1, DataHelper.distributionAmount0, proofForIndex1
        );
        (,,, uint256 endTime) = distribution.distributions(distributionId);
        vm.warp(endTime + 1);
        vm.prank(owner);
        vm.expectRevert(DividendDistribution.DistributionEnded.selector);
        distribution.distribute(
            distributionId, DataHelper.distributionAddress1, DataHelper.distributionAmount1, proofForIndex1
        );
    }

    function testReclaimed() public {
        uint256 _totalDistribution =
            DataHelper.distributionAmount0 + DataHelper.distributionAmount1 + DataHelper.distributionAmount2;

        token.mint(owner, _totalDistribution);

        vm.prank(owner);
        token.approve(address(distribution), _totalDistribution);
        vm.prank(owner);
        distribution.createDistribution(address(token), root, _totalDistribution, block.timestamp + 1);
        assertEq(IERC20(address(token)).balanceOf(address(distribution)), _totalDistribution);
        assertEq(IERC20(address(token)).balanceOf(owner), 0);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user);
        distribution.reclaimDistribution(0);

        vm.expectRevert(DividendDistribution.DistributionRunning.selector);
        vm.prank(owner);
        distribution.reclaimDistribution(0);

        (,,, uint256 endTime) = distribution.distributions(0);
        vm.warp(endTime + 1);

        vm.expectEmit(true, true, true, true);
        emit DistributionReclaimed(0, _totalDistribution);
        vm.prank(owner);
        distribution.reclaimDistribution(0);

        assertEq(IERC20(address(token)).balanceOf(address(distribution)), 0);
        assertEq(IERC20(address(token)).balanceOf(owner), _totalDistribution);
    }
}
