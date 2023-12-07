// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DividendDistribution} from "../../src/dividend/DividendDistribution.sol";
import {DualDistributor} from "../../src/dividend/DualDistributor.sol";
import {TransferRestrictor, ITransferRestrictor} from "../../src/TransferRestrictor.sol";
import {WrappedDShare} from "../../src/WrappedDShare.sol";
import {DShare} from "../../src/DShare.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DualDistributorTest is Test {
    DividendDistribution distribution;
    DualDistributor dualDistributor;
    TransferRestrictor restrictor;
    WrappedDShare xToken;
    DShare dtoken;
    MockERC20 token;

    uint256 userPrivateKey;
    uint256 ownerPrivateKey;

    address user = address(1);
    address user2 = address(2);
    address admin = address(3);
    address distributor = address(4);

    event NewDistribution(
        uint256 indexed distributionId, address indexed DShare, uint256 usdcAmount, uint256 dShareAmount
    );

    event NewDividendDistributionSet(address indexed newDivividendDistribution);

    function setUp() public {
        vm.startPrank(admin);
        restrictor = new TransferRestrictor(admin);
        token = new MockERC20("Money", "$", 6);
        DShare tokenImplementation = new DShare();
        dtoken = DShare(
            address(
                new ERC1967Proxy(
                    address(tokenImplementation),
                    abi.encodeCall(DShare.initialize, (admin, "Dinari Token", "dTKN", restrictor))
                )
            )
        );
        WrappedDShare xtokenImplementation = new WrappedDShare();
        xToken = WrappedDShare(
            address(
                new ERC1967Proxy(
                    address(xtokenImplementation),
                    abi.encodeCall(WrappedDShare.initialize, (admin, dtoken, "Dinari xdToken", "xdTKN"))
                )
            )
        );

        dtoken.grantRole(dtoken.MINTER_ROLE(), admin);

        distribution = new DividendDistribution(admin);

        distribution.grantRole(distribution.DISTRIBUTOR_ROLE(), distributor);
        dualDistributor = new DualDistributor(admin, address(distribution));
        dualDistributor.grantRole(dualDistributor.DISTRIBUTOR_ROLE(), distributor);
        distribution.grantRole(distribution.DISTRIBUTOR_ROLE(), address(dualDistributor));

        vm.stopPrank();
    }

    function testStateVar() public {
        assertEq(dualDistributor.dividendDistribution(), address(distribution));
    }

    function testSetDividendDistributionZeroAddressReverts() public {
        vm.expectRevert(DualDistributor.ZeroAddress.selector);
        vm.prank(admin);
        dualDistributor.setDividendDistribution(address(0));
    }

    function testSetDividendDistribution(address account) public {
        vm.assume(account != address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, distribution.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        dualDistributor.setDividendDistribution(account);

        vm.expectEmit(true, true, true, true);
        emit NewDividendDistributionSet(account);
        vm.prank(admin);
        dualDistributor.setDividendDistribution(account);
        assertEq(dualDistributor.dividendDistribution(), account);
    }

    function testSetWrappedDShareForDShareZeroAddressReverts() public {
        vm.expectRevert(DualDistributor.ZeroAddress.selector);
        vm.prank(admin);
        dualDistributor.setWrappedDShareForDShare(address(0), address(1));
    }

    function testSetWrappedDShareForDShare(address _dShare, address _WrappedDShare) public {
        vm.assume(_dShare != address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, distribution.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        dualDistributor.setWrappedDShareForDShare(_dShare, _WrappedDShare);

        vm.prank(admin);
        dualDistributor.setWrappedDShareForDShare(_dShare, _WrappedDShare);
        assertEq(dualDistributor.dShareToWrappedDShare(_dShare), _WrappedDShare);
    }

    function testDistribute(uint256 amountA, uint256 amountB, uint256 endTime) public {
        vm.assume(endTime > block.timestamp + distribution.minDistributionTime());

        vm.startPrank(admin);
        token.mint(address(dualDistributor), amountA);
        dtoken.mint(address(dualDistributor), amountB);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), distribution.DISTRIBUTOR_ROLE()
            )
        );
        dualDistributor.distribute(address(token), address(dtoken), amountA, amountB, endTime);

        vm.prank(distributor);
        vm.expectRevert(DualDistributor.ZeroAddress.selector);
        dualDistributor.distribute(address(token), address(dtoken), amountA, amountB, endTime);

        vm.prank(admin);
        dualDistributor.setWrappedDShareForDShare(address(dtoken), address(xToken));

        vm.prank(distributor);
        vm.expectRevert(DualDistributor.ZeroAddress.selector);
        dualDistributor.distribute(address(0), address(dtoken), amountA, amountB, endTime);

        vm.prank(distributor);
        vm.expectEmit(true, true, true, true);
        emit NewDistribution(0, address(dtoken), amountA, amountB);
        dualDistributor.distribute(address(token), address(dtoken), amountA, amountB, endTime);
    }
}
