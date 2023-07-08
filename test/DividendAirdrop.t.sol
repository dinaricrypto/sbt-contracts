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
    uint256 public distributorPrivateKey;
    uint256 public ownerPrivateKey;

    address public user;
    address public distributor;
    address public owner;

    uint256[] public resultsArray;

    struct HashAndDataTuple {
        uint256 originalData;
        bytes32 hash;
    }

    event Claimed(uint256 airdropId, address indexed account, uint256 amount);
    event AirdropReclaimed(uint256 airdropId, uint256 totalReclaimed);

    function setUp() public {
        userPrivateKey = 0x1;
        distributorPrivateKey = 0x2;
        ownerPrivateKey = 0x3;

        merkle = new Merkle();

        token = new MockERC20("Money", "$", 6);

        user = vm.addr(userPrivateKey);
        distributor = vm.addr(distributorPrivateKey);
        owner = vm.addr(ownerPrivateKey);
        vm.prank(owner);
        airdrop = new DividendAirdrop(address(token), distributor, 1000);
    }

    function testDeployment(address _token, address _distributor, uint256 _claimWindow) public {
        vm.prank(owner);
        DividendAirdrop newAirdrop = new DividendAirdrop(_token, _distributor, _claimWindow);
        assertEq(newAirdrop.token(), _token);
        assertEq(newAirdrop.distributor(), _distributor);
        assertEq(newAirdrop.claimWindow(), _claimWindow);
        assertEq(newAirdrop.nextAirdropId(), 0);
        assertEq(newAirdrop.owner(), owner);

        vm.expectRevert("Ownable: caller is not the owner");
        newAirdrop.setNewDistributor(_distributor);
        vm.expectRevert("Ownable: caller is not the owner");
        newAirdrop.setClaimWindow(_claimWindow);

        vm.startPrank(owner);
        newAirdrop.setNewDistributor(_distributor);
        newAirdrop.setClaimWindow(_claimWindow);
        vm.stopPrank();
    }

    function testCreateNewAirdrop(bytes32 _merkleRoot, uint256 _totalDistribution) public {
        vm.assume(_totalDistribution < 1e8);
        assertEq(IERC20(address(token)).balanceOf(address(airdrop)), 0);
        vm.expectRevert(DividendAirdrop.NotDistributor.selector);
        airdrop.createAirdrop(_merkleRoot, _totalDistribution);

        token.mint(distributor, _totalDistribution);

        vm.prank(distributor);
        token.approve(address(airdrop), _totalDistribution);

        vm.prank(distributor);
        airdrop.createAirdrop(_merkleRoot, _totalDistribution);

        assertEq(IERC20(address(token)).balanceOf(address(airdrop)), _totalDistribution);
        assertEq(IERC20(address(token)).balanceOf(distributor), 0);
    }

    function testClaim(uint256 _totalDistribution) public {
        vm.assume(
            _totalDistribution > DataHelper.airdropAmount0 + DataHelper.airdropAmount1 + DataHelper.airdropAmount2
        );
        bytes32[] memory data = generateData(address(airdrop));

        // Generate the root using the copy
        bytes32 root = merkle.getRoot(data);

        // Generate proof for index 0 using the copy
        bytes32[] memory proofForIndex0 = merkle.getProof(data, 0);

        // Generate proof for index 1 using the copy
        bytes32[] memory proofForIndex1 = merkle.getProof(data, 1);

        token.mint(distributor, _totalDistribution);

        vm.prank(distributor);
        token.approve(address(airdrop), _totalDistribution);
        vm.prank(distributor);
        uint256 airdropId = airdrop.createAirdrop(root, _totalDistribution);

        vm.expectEmit(true, true, true, true);
        emit Claimed(airdropId, DataHelper.airdropAddress0, DataHelper.airdropAmount0);
        vm.prank(DataHelper.airdropAddress0);
        airdrop.claim(airdropId, DataHelper.airdropAddress0, DataHelper.airdropAmount0, proofForIndex0);
        assertEq(IERC20(address(token)).balanceOf(DataHelper.airdropAddress0), DataHelper.airdropAmount0);

        vm.expectRevert(DividendAirdrop.AlreadyClaimed.selector);
        vm.prank(DataHelper.airdropAddress0);
        airdrop.claim(airdropId, DataHelper.airdropAddress0, DataHelper.airdropAmount0, proofForIndex0);

        vm.expectRevert(DividendAirdrop.InvalidProof.selector);
        vm.prank(DataHelper.airdropAddress0);
        airdrop.claim(airdropId, DataHelper.airdropAddress1, DataHelper.airdropAmount0, proofForIndex1);
        (,, uint256 endTime,) = airdrop.airdrops(0);
        vm.warp(endTime + 1);
        vm.prank(DataHelper.airdropAddress1);
        vm.expectRevert(DividendAirdrop.AirdropEnded.selector);
        airdrop.claim(airdropId, DataHelper.airdropAddress1, DataHelper.airdropAmount1, proofForIndex1);
    }

    function testReclaimed(uint256 _totalDistribution) public {
        vm.assume(
            _totalDistribution > DataHelper.airdropAmount0 + DataHelper.airdropAmount1 + DataHelper.airdropAmount2
        );
        bytes32[] memory data = generateData(address(airdrop));
        // Generate the root using the copy
        bytes32 root = merkle.getRoot(data);

        token.mint(distributor, _totalDistribution);

        vm.prank(distributor);
        token.approve(address(airdrop), _totalDistribution);
        vm.prank(distributor);
        airdrop.createAirdrop(root, _totalDistribution);
        assertEq(IERC20(address(token)).balanceOf(address(airdrop)), _totalDistribution);
        assertEq(IERC20(address(token)).balanceOf(distributor), 0);

        vm.expectRevert(DividendAirdrop.NotDistributor.selector);
        vm.prank(user);
        airdrop.reclaimedAirdrop(0);

        vm.expectRevert(DividendAirdrop.AirdropStillRunning.selector);
        vm.prank(distributor);
        airdrop.reclaimedAirdrop(0);

        (,, uint256 endTime,) = airdrop.airdrops(0);
        vm.warp(endTime + 1);

        vm.expectEmit(true, true, true, true);
        emit AirdropReclaimed(0, _totalDistribution);
        vm.prank(distributor);
        airdrop.reclaimedAirdrop(0);

        assertEq(IERC20(address(token)).balanceOf(address(airdrop)), 0);
        assertEq(IERC20(address(token)).balanceOf(distributor), _totalDistribution);
    }
}
