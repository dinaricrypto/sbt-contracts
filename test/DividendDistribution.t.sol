// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DividendDistributionTest is Test {
    DividendDistribution distribution;
    MockERC20 token;

    uint256 public userPrivateKey;
    uint256 public user2PrivateKey;
    uint256 public adminPrivateKey;

    address public user;
    address public user2;
    address public admin;
    address public distributor = address(4);

    struct HashAndDataTuple {
        uint256 originalData;
        bytes32 hash;
    }

    event MinDistributionTimeSet(uint64 minDistributionTime);
    event Distributed(uint256 indexed distributionId, address indexed account, uint256 amount);
    event NewDistributionCreated(
        uint256 indexed distributionId, uint256 totalDistribution, uint256 startDate, uint256 endDate
    );
    event DistributionReclaimed(uint256 indexed distributionId, uint256 totalReclaimed);

    function setUp() public {
        userPrivateKey = 0x01;
        user2PrivateKey = 0x02;
        adminPrivateKey = 0x03;
        user = vm.addr(userPrivateKey);
        user2 = vm.addr(user2PrivateKey);
        admin = vm.addr(adminPrivateKey);

        vm.startPrank(admin);
        token = new MockERC20("Money", "$", 6);
        DividendDistribution distributionImpl = new DividendDistribution();
        distribution = DividendDistribution(
            address(
                new ERC1967Proxy(address(distributionImpl), abi.encodeCall(distributionImpl.initialize, (admin, admin)))
            )
        );

        distribution.grantRole(distribution.DISTRIBUTOR_ROLE(), distributor);
        vm.stopPrank();
    }

    function testSetMinDistributionTime(uint64 minDistributionTime) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, distribution.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        distribution.setMinDistributionTime(minDistributionTime);

        vm.expectEmit(true, true, true, true);
        emit MinDistributionTimeSet(minDistributionTime);
        vm.prank(admin);
        distribution.setMinDistributionTime(minDistributionTime);
        assertEq(distribution.minDistributionTime(), minDistributionTime);
    }

    function testCreateNewDistribution(uint256 totalDistribution, uint256 _endTime) public {
        vm.assume(totalDistribution < 1e8);
        assertEq(IERC20(address(token)).balanceOf(address(distribution)), 0);

        vm.prank(admin);
        token.mint(distributor, totalDistribution);

        vm.prank(distributor);
        token.approve(address(distribution), totalDistribution);

        if (_endTime <= block.timestamp + distribution.minDistributionTime()) {
            vm.expectRevert(DividendDistribution.EndTimeBeforeMin.selector);
            vm.prank(distributor);
            distribution.createDistribution(address(token), totalDistribution, _endTime);
        } else {
            vm.expectEmit(true, true, true, true);
            emit NewDistributionCreated(0, totalDistribution, block.timestamp, _endTime);
            vm.prank(distributor);
            distribution.createDistribution(address(token), totalDistribution, _endTime);
            assertEq(IERC20(address(token)).balanceOf(address(distribution)), totalDistribution);
            assertEq(IERC20(address(token)).balanceOf(distributor), 0);
        }
    }

    function testCreateDistributionNotDistributorReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, distribution.DISTRIBUTOR_ROLE()
            )
        );
        vm.prank(user);
        distribution.createDistribution(address(token), 100, block.timestamp + 1);
    }

    function testDistribute(uint256 totalDistribution, uint256 distribution1) public {
        vm.assume(distribution1 < totalDistribution);

        token.mint(distributor, totalDistribution);

        vm.prank(distributor);
        token.approve(address(distribution), totalDistribution);
        vm.startPrank(distributor);
        uint256 distributionId = distribution.createDistribution(
            address(token), totalDistribution, block.timestamp + distribution.minDistributionTime() + 1
        );
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, distribution.DISTRIBUTOR_ROLE()
            )
        );
        vm.prank(user);
        distribution.distribute(distributionId, user, distribution1);

        vm.expectEmit(true, true, true, true);
        emit Distributed(distributionId, user, distribution1);
        vm.prank(distributor);
        distribution.distribute(distributionId, user, distribution1);
        assertEq(token.balanceOf(user), distribution1);

        (,, uint256 endTime) = distribution.distributions(distributionId);
        vm.warp(endTime + 1);
        vm.prank(distributor);
        vm.expectRevert(DividendDistribution.DistributionEnded.selector);
        distribution.distribute(distributionId, user, distribution1);
    }

    function testReclaimed(uint256 totalDistribution) public {
        token.mint(distributor, totalDistribution);

        vm.prank(distributor);
        token.approve(address(distribution), totalDistribution);
        vm.startPrank(distributor);
        distribution.createDistribution(
            address(token), totalDistribution, block.timestamp + distribution.minDistributionTime() + 1
        );
        vm.stopPrank();
        assertEq(IERC20(address(token)).balanceOf(address(distribution)), totalDistribution);
        assertEq(IERC20(address(token)).balanceOf(distributor), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, distribution.DISTRIBUTOR_ROLE()
            )
        );
        vm.prank(user);
        distribution.reclaimDistribution(0);

        vm.expectRevert(DividendDistribution.DistributionRunning.selector);
        vm.prank(distributor);
        distribution.reclaimDistribution(0);

        vm.expectRevert(DividendDistribution.NotReclaimable.selector);
        vm.prank(distributor);
        distribution.reclaimDistribution(1);

        (,, uint256 endTime) = distribution.distributions(0);
        vm.warp(endTime + 1);

        vm.expectEmit(true, true, true, true);
        emit DistributionReclaimed(0, totalDistribution);
        vm.prank(distributor);
        distribution.reclaimDistribution(0);

        assertEq(IERC20(address(token)).balanceOf(address(distribution)), 0);
        assertEq(IERC20(address(token)).balanceOf(distributor), totalDistribution);
    }
}
