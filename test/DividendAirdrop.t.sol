// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DividendAirdrop} from "../src/dividend-airdrops/DividendAirdrop.sol";
import {DataHelper} from "./utils/DataHelper.sol";
import {Merkle} from "murky/Merkle.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

contract DividendAirdropTest is Test, DataHelper {
    Merkle merkle;

    DividendAirdrop airdrop;
    MockERC20 token;

    uint256 public userPrivateKey;
    uint256 public ownerPrivateKey;

    address public user;
    address public owner;

    uint256[] public resultsArray;

    struct HashAndDataTuple {
        uint256 originalData;
        bytes32 hash;
    }

    event Distributed(uint256 airdropId, address indexed account, uint256 amount);
    event AirdropReclaimed(uint256 airdropId, uint256 totalReclaimed);

    function setUp() public {
        userPrivateKey = 0x1;
        ownerPrivateKey = 0x2;

        merkle = new Merkle();

        token = new MockERC20("Money", "$", 6);

        user = vm.addr(userPrivateKey);
        owner = vm.addr(ownerPrivateKey);
        vm.prank(owner);
        airdrop = new DividendAirdrop(address(token), 90 days);
    }

    function testDeployment(address _token, uint256 _claimWindow) public {
        vm.prank(owner);
        DividendAirdrop newAirdrop = new DividendAirdrop(_token, _claimWindow);
        assertEq(newAirdrop.token(), _token);
        assertEq(newAirdrop.claimWindow(), _claimWindow);
        assertEq(newAirdrop.nextAirdropId(), 0);

        vm.expectRevert("Ownable: caller is not the owner");
        newAirdrop.setClaimWindow(_claimWindow);

        vm.prank(owner);
        newAirdrop.setClaimWindow(_claimWindow);
    }

    function testCreateNewAirdrop(bytes32 _merkleRoot, uint256 _totalDistribution) public {
        vm.assume(_totalDistribution < 1e8);
        assertEq(IERC20(address(token)).balanceOf(address(airdrop)), 0);
        vm.expectRevert("Ownable: caller is not the owner");
        airdrop.createAirdrop(_merkleRoot, _totalDistribution);

        token.mint(owner, _totalDistribution);

        vm.prank(owner);
        token.approve(address(airdrop), _totalDistribution);

        vm.prank(owner);
        airdrop.createAirdrop(_merkleRoot, _totalDistribution);

        assertEq(IERC20(address(token)).balanceOf(address(airdrop)), _totalDistribution);
        assertEq(IERC20(address(token)).balanceOf(owner), 0);
    }

    function testDistribute() public {
        uint256 _totalDistribution = DataHelper.airdropAmount0 + DataHelper.airdropAmount1 + DataHelper.airdropAmount2;

        bytes32[] memory data = generateData(address(airdrop));

        // Generate the root using the copy
        bytes32 root = merkle.getRoot(data);

        // Generate proof for index 0 using the copy
        bytes32[] memory proofForIndex0 = merkle.getProof(data, 0);

        // Generate proof for index 1 using the copy
        bytes32[] memory proofForIndex1 = merkle.getProof(data, 1);

        token.mint(owner, _totalDistribution);

        vm.prank(owner);
        token.approve(address(airdrop), _totalDistribution);
        vm.prank(owner);
        uint256 airdropId = airdrop.createAirdrop(root, _totalDistribution);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(DataHelper.airdropAddress0);
        airdrop.distribute(airdropId, DataHelper.airdropAddress0, DataHelper.airdropAmount0, proofForIndex0);

        vm.expectEmit(true, true, true, true);
        emit Distributed(airdropId, DataHelper.airdropAddress0, DataHelper.airdropAmount0);
        vm.prank(owner);
        airdrop.distribute(airdropId, DataHelper.airdropAddress0, DataHelper.airdropAmount0, proofForIndex0);
        assertEq(IERC20(address(token)).balanceOf(DataHelper.airdropAddress0), DataHelper.airdropAmount0);

        vm.expectRevert(DividendAirdrop.AlreadyClaimed.selector);
        vm.prank(owner);
        airdrop.distribute(airdropId, DataHelper.airdropAddress0, DataHelper.airdropAmount0, proofForIndex0);

        vm.expectRevert(DividendAirdrop.InvalidProof.selector);
        vm.prank(owner);
        airdrop.distribute(airdropId, DataHelper.airdropAddress1, DataHelper.airdropAmount0, proofForIndex1);
        (,, uint256 endTime,) = airdrop.airdrops(0);
        vm.warp(endTime + 1);
        vm.prank(owner);
        vm.expectRevert(DividendAirdrop.AirdropEnded.selector);
        airdrop.distribute(airdropId, DataHelper.airdropAddress1, DataHelper.airdropAmount1, proofForIndex1);
    }

    function testReclaimed(uint256 _totalDistribution) public {
        vm.assume(
            _totalDistribution > DataHelper.airdropAmount0 + DataHelper.airdropAmount1 + DataHelper.airdropAmount2
        );
        bytes32[] memory data = generateData(address(airdrop));
        // Generate the root using the copy
        bytes32 root = merkle.getRoot(data);

        token.mint(owner, _totalDistribution);

        vm.prank(owner);
        token.approve(address(airdrop), _totalDistribution);
        vm.prank(owner);
        airdrop.createAirdrop(root, _totalDistribution);
        assertEq(IERC20(address(token)).balanceOf(address(airdrop)), _totalDistribution);
        assertEq(IERC20(address(token)).balanceOf(owner), 0);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user);
        airdrop.reclaimedAirdrop(0);

        vm.expectRevert(DividendAirdrop.AirdropStillRunning.selector);
        vm.prank(owner);
        airdrop.reclaimedAirdrop(0);

        (,, uint256 endTime,) = airdrop.airdrops(0);
        vm.warp(endTime + 1);

        vm.expectEmit(true, true, true, true);
        emit AirdropReclaimed(0, _totalDistribution);
        vm.prank(owner);
        airdrop.reclaimedAirdrop(0);

        assertEq(IERC20(address(token)).balanceOf(address(airdrop)), 0);
        assertEq(IERC20(address(token)).balanceOf(owner), _totalDistribution);
    }
}
