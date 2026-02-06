// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IDShare} from "../src/IDShare.sol";

/// @notice Mock DShare token for testing mint functionality
contract MockDShare is MockERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) MockERC20(name_, symbol_, decimals_) {}

    function mint(address to, uint256 value) public override {
        _mint(to, value);
    }
}

contract DividendDistributionTest is Test {
    DividendDistribution distribution;
    MockERC20 token;
    MockDShare dshareToken;

    uint256 public userPrivateKey;
    uint256 public user2PrivateKey;
    uint256 public adminPrivateKey;

    address public user;
    address public user2;
    address public admin;
    address public distributor = address(4);
    address public withholder = address(5);
    address public revenueVault = address(6);

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
    event DividendMinted(
        bytes32 indexed brokerageDividendId, address indexed target, address indexed token, uint256 amount
    );
    event DistributionSent(
        bytes32 indexed distributionId, address indexed recipient, address indexed token, uint256 amount
    );
    event WithholdingSent(
        bytes32 indexed withholdingId, address indexed recipient, address indexed token, uint256 amount
    );
    event FeeSent(bytes32 indexed feeId, address indexed recipient, address indexed token, uint256 amount);

    function setUp() public {
        userPrivateKey = 0x01;
        user2PrivateKey = 0x02;
        adminPrivateKey = 0x03;
        user = vm.addr(userPrivateKey);
        user2 = vm.addr(user2PrivateKey);
        admin = vm.addr(adminPrivateKey);

        vm.startPrank(admin);
        token = new MockERC20("Money", "$", 6);
        dshareToken = new MockDShare("DShare", "DS", 18);
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

    // ------------------- mintDividend Tests ------------------- //

    function testMintDividendToWallet() public {
        bytes32 brokerageDividendId = keccak256("brokerage-dividend-1");
        uint256 amount = 1000e18;

        vm.expectEmit(true, true, true, true);
        emit DividendMinted(brokerageDividendId, user, address(dshareToken), amount);

        vm.prank(distributor);
        distribution.mintDividend(address(dshareToken), amount, user, brokerageDividendId);

        assertEq(dshareToken.balanceOf(user), amount);
        assertTrue(distribution.dividendMinted(brokerageDividendId));
    }

    function testMintDividendToContract() public {
        bytes32 brokerageDividendId = keccak256("brokerage-dividend-2");
        uint256 amount = 5000e18;

        vm.expectEmit(true, true, true, true);
        emit DividendMinted(brokerageDividendId, address(distribution), address(dshareToken), amount);

        vm.prank(distributor);
        distribution.mintDividend(address(dshareToken), amount, address(distribution), brokerageDividendId);

        assertEq(dshareToken.balanceOf(address(distribution)), amount);
    }

    function testMintDividendIdempotency() public {
        bytes32 brokerageDividendId = keccak256("brokerage-dividend-3");
        uint256 amount = 1000e18;

        vm.prank(distributor);
        distribution.mintDividend(address(dshareToken), amount, user, brokerageDividendId);

        vm.expectRevert(
            abi.encodeWithSelector(DividendDistribution.DividendAlreadyMinted.selector, brokerageDividendId)
        );
        vm.prank(distributor);
        distribution.mintDividend(address(dshareToken), amount, user, brokerageDividendId);
    }

    function testMintDividendOnlyDistributor() public {
        bytes32 brokerageDividendId = keccak256("brokerage-dividend-4");
        uint256 amount = 1000e18;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, distribution.DISTRIBUTOR_ROLE()
            )
        );
        vm.prank(user);
        distribution.mintDividend(address(dshareToken), amount, user, brokerageDividendId);
    }

    function testMintDividendZeroChecks() public {
        bytes32 brokerageDividendId = keccak256("brokerage-dividend-5");
        uint256 amount = 1000e18;

        vm.expectRevert(DividendDistribution.ZeroAddress.selector);
        vm.prank(distributor);
        distribution.mintDividend(address(0), amount, user, brokerageDividendId);

        vm.expectRevert(DividendDistribution.ZeroAddress.selector);
        vm.prank(distributor);
        distribution.mintDividend(address(dshareToken), amount, address(0), brokerageDividendId);

        vm.expectRevert(DividendDistribution.ZeroAmount.selector);
        vm.prank(distributor);
        distribution.mintDividend(address(dshareToken), 0, user, brokerageDividendId);
    }

    // ------------------- sendDistribution Tests ------------------- //

    function testSendDistribution() public {
        // First mint to contract
        bytes32 brokerageDividendId = keccak256("brokerage-dividend-send-1");
        uint256 totalAmount = 5000e18;
        vm.prank(distributor);
        distribution.mintDividend(address(dshareToken), totalAmount, address(distribution), brokerageDividendId);

        // Send distribution to user
        bytes32 distributionId = keccak256("distribution-1");
        uint256 userAmount = 1000e18;

        vm.expectEmit(true, true, true, true);
        emit DistributionSent(distributionId, user, address(dshareToken), userAmount);

        vm.prank(distributor);
        distribution.sendDistribution(address(dshareToken), userAmount, user, distributionId);

        assertEq(dshareToken.balanceOf(user), userAmount);
        assertEq(dshareToken.balanceOf(address(distribution)), totalAmount - userAmount);
        assertTrue(distribution.distributionSent(distributionId));
    }

    function testSendDistributionIdempotency() public {
        bytes32 brokerageDividendId = keccak256("brokerage-dividend-send-2");
        vm.prank(distributor);
        distribution.mintDividend(address(dshareToken), 5000e18, address(distribution), brokerageDividendId);

        bytes32 distributionId = keccak256("distribution-2");
        uint256 amount = 1000e18;

        vm.prank(distributor);
        distribution.sendDistribution(address(dshareToken), amount, user, distributionId);

        vm.expectRevert(abi.encodeWithSelector(DividendDistribution.DistributionAlreadySent.selector, distributionId));
        vm.prank(distributor);
        distribution.sendDistribution(address(dshareToken), amount, user, distributionId);
    }

    function testSendDistributionOnlyDistributor() public {
        bytes32 distributionId = keccak256("distribution-3");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, distribution.DISTRIBUTOR_ROLE()
            )
        );
        vm.prank(user);
        distribution.sendDistribution(address(dshareToken), 1000e18, user, distributionId);
    }

    function testSendDistributionZeroChecks() public {
        bytes32 distributionId = keccak256("distribution-4");
        uint256 amount = 1000e18;

        vm.expectRevert(DividendDistribution.ZeroAddress.selector);
        vm.prank(distributor);
        distribution.sendDistribution(address(0), amount, user, distributionId);

        vm.expectRevert(DividendDistribution.ZeroAddress.selector);
        vm.prank(distributor);
        distribution.sendDistribution(address(dshareToken), amount, address(0), distributionId);

        vm.expectRevert(DividendDistribution.ZeroAmount.selector);
        vm.prank(distributor);
        distribution.sendDistribution(address(dshareToken), 0, user, distributionId);
    }

    // ------------------- sendWithholding Tests ------------------- //

    function testSendWithholding() public {
        bytes32 brokerageDividendId = keccak256("brokerage-dividend-wh-1");
        uint256 totalAmount = 5000e18;
        vm.prank(distributor);
        distribution.mintDividend(address(dshareToken), totalAmount, address(distribution), brokerageDividendId);

        bytes32 withholdingId = keccak256("withholding-1");
        uint256 withholdingAmount = 200e18;

        vm.expectEmit(true, true, true, true);
        emit WithholdingSent(withholdingId, withholder, address(dshareToken), withholdingAmount);

        vm.prank(distributor);
        distribution.sendWithholding(address(dshareToken), withholdingAmount, withholder, withholdingId);

        assertEq(dshareToken.balanceOf(withholder), withholdingAmount);
        assertTrue(distribution.withholdingSent(withholdingId));
    }

    function testSendWithholdingIdempotency() public {
        bytes32 brokerageDividendId = keccak256("brokerage-dividend-wh-2");
        vm.prank(distributor);
        distribution.mintDividend(address(dshareToken), 5000e18, address(distribution), brokerageDividendId);

        bytes32 withholdingId = keccak256("withholding-2");
        uint256 amount = 200e18;

        vm.prank(distributor);
        distribution.sendWithholding(address(dshareToken), amount, withholder, withholdingId);

        vm.expectRevert(abi.encodeWithSelector(DividendDistribution.WithholdingAlreadySent.selector, withholdingId));
        vm.prank(distributor);
        distribution.sendWithholding(address(dshareToken), amount, withholder, withholdingId);
    }

    function testSendWithholdingOnlyDistributor() public {
        bytes32 withholdingId = keccak256("withholding-3");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, distribution.DISTRIBUTOR_ROLE()
            )
        );
        vm.prank(user);
        distribution.sendWithholding(address(dshareToken), 200e18, withholder, withholdingId);
    }

    function testSendWithholdingZeroChecks() public {
        bytes32 withholdingId = keccak256("withholding-4");
        uint256 amount = 200e18;

        vm.expectRevert(DividendDistribution.ZeroAddress.selector);
        vm.prank(distributor);
        distribution.sendWithholding(address(0), amount, withholder, withholdingId);

        vm.expectRevert(DividendDistribution.ZeroAddress.selector);
        vm.prank(distributor);
        distribution.sendWithholding(address(dshareToken), amount, address(0), withholdingId);

        vm.expectRevert(DividendDistribution.ZeroAmount.selector);
        vm.prank(distributor);
        distribution.sendWithholding(address(dshareToken), 0, withholder, withholdingId);
    }

    // ------------------- sendFee Tests ------------------- //

    function testSendFee() public {
        bytes32 brokerageDividendId = keccak256("brokerage-dividend-fee-1");
        uint256 totalAmount = 5000e18;
        vm.prank(distributor);
        distribution.mintDividend(address(dshareToken), totalAmount, address(distribution), brokerageDividendId);

        bytes32 feeId = keccak256("fee-1");
        uint256 feeAmount = 50e18;

        vm.expectEmit(true, true, true, true);
        emit FeeSent(feeId, revenueVault, address(dshareToken), feeAmount);

        vm.prank(distributor);
        distribution.sendFee(address(dshareToken), feeAmount, revenueVault, feeId);

        assertEq(dshareToken.balanceOf(revenueVault), feeAmount);
        assertTrue(distribution.feeSent(feeId));
    }

    function testSendFeeIdempotency() public {
        bytes32 brokerageDividendId = keccak256("brokerage-dividend-fee-2");
        vm.prank(distributor);
        distribution.mintDividend(address(dshareToken), 5000e18, address(distribution), brokerageDividendId);

        bytes32 feeId = keccak256("fee-2");
        uint256 feeAmount = 50e18;

        vm.prank(distributor);
        distribution.sendFee(address(dshareToken), feeAmount, revenueVault, feeId);

        vm.expectRevert(abi.encodeWithSelector(DividendDistribution.FeeAlreadySent.selector, feeId));
        vm.prank(distributor);
        distribution.sendFee(address(dshareToken), feeAmount, revenueVault, feeId);
    }

    function testSendFeeOnlyDistributor() public {
        bytes32 feeId = keccak256("fee-3");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, distribution.DISTRIBUTOR_ROLE()
            )
        );
        vm.prank(user);
        distribution.sendFee(address(dshareToken), 50e18, revenueVault, feeId);
    }

    function testSendFeeZeroChecks() public {
        bytes32 feeId = keccak256("fee-4");
        uint256 feeAmount = 50e18;

        vm.expectRevert(DividendDistribution.ZeroAddress.selector);
        vm.prank(distributor);
        distribution.sendFee(address(0), feeAmount, revenueVault, feeId);

        vm.expectRevert(DividendDistribution.ZeroAddress.selector);
        vm.prank(distributor);
        distribution.sendFee(address(dshareToken), feeAmount, address(0), feeId);

        vm.expectRevert(DividendDistribution.ZeroAmount.selector);
        vm.prank(distributor);
        distribution.sendFee(address(dshareToken), 0, revenueVault, feeId);
    }

    // ------------------- Full Omnibus Flow Test ------------------- //

    function testFullOmnibusFlow() public {
        // Step 1: Mint total dividend to contract
        bytes32 brokerageDividendId = keccak256("omnibus-dividend-1");
        uint256 totalAmount = 10000e18;

        vm.prank(distributor);
        distribution.mintDividend(address(dshareToken), totalAmount, address(distribution), brokerageDividendId);
        assertEq(dshareToken.balanceOf(address(distribution)), totalAmount);

        // Step 2: Send distributions to users
        bytes32 dist1 = keccak256("dist-user1");
        bytes32 dist2 = keccak256("dist-user2");
        uint256 user1Amount = 3000e18;
        uint256 user2Amount = 4000e18;

        vm.startPrank(distributor);
        distribution.sendDistribution(address(dshareToken), user1Amount, user, dist1);
        distribution.sendDistribution(address(dshareToken), user2Amount, user2, dist2);

        // Step 3: Send withholding
        bytes32 whId = keccak256("wh-user1");
        uint256 withholdingAmount = 500e18;
        distribution.sendWithholding(address(dshareToken), withholdingAmount, withholder, whId);

        // Step 4: Send fee
        bytes32 feeId = keccak256("fee-omnibus");
        uint256 feeAmount = 100e18;
        distribution.sendFee(address(dshareToken), feeAmount, revenueVault, feeId);
        vm.stopPrank();

        // Verify final balances
        assertEq(dshareToken.balanceOf(user), user1Amount);
        assertEq(dshareToken.balanceOf(user2), user2Amount);
        assertEq(dshareToken.balanceOf(withholder), withholdingAmount);
        assertEq(dshareToken.balanceOf(revenueVault), feeAmount);
        assertEq(
            dshareToken.balanceOf(address(distribution)),
            totalAmount - user1Amount - user2Amount - withholdingAmount - feeAmount
        );
    }
}
