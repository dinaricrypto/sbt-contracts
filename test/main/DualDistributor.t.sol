// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DividendDistribution} from "../../src/dividend/DividendDistribution.sol";
import {DualDistributor} from "../../src/dividend/DualDistributor.sol";
import {TransferRestrictor, ITransferRestrictor} from "../../src/TransferRestrictor.sol";
import {XDShare} from "../../src/dividend/XDShare.sol";
import {DShare} from "../../src/DShare.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DualDistributorTest is Test {
    DividendDistribution distribution;
    DualDistributor dualDistributor;
    TransferRestrictor restrictor;
    XDShare xToken;
    DShare dtoken;
    MockERC20 token;

    uint256 userPrivateKey;
    uint256 ownerPrivateKey;

    address user = address(1);
    address user2 = address(2);
    address distributor = address(4);

    event NewDistribution(
        uint256 indexed distributionId, address indexed DShare, uint256 usdcAmount, uint256 dShareAmount
    );

    event NewDividendDistributionSet(address indexed newDivividendDistribution);

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        token = new MockERC20("Money", "$", 6);
        DShare tokenImplementation = new DShare();
        dtoken = DShare(
            address(
                new ERC1967Proxy(
                    address(tokenImplementation),
                    abi.encodeCall(DShare.initialize, (address(this), "Dinari Token", "dTKN", restrictor))
                )
            )
        );
        XDShare xtokenImplementation = new XDShare();
        xToken = XDShare(
            address(
                new ERC1967Proxy(
                    address(xtokenImplementation),
                    abi.encodeCall(XDShare.initialize, (dtoken, "Dinari xdToken", "xdTKN"))
                )
            )
        );

        dtoken.grantRole(dtoken.MINTER_ROLE(), address(this));

        distribution = new DividendDistribution(address(this));

        distribution.grantRole(distribution.DISTRIBUTOR_ROLE(), distributor);
        dualDistributor = new DualDistributor(address(this), address(distribution));
        dualDistributor.grantRole(dualDistributor.DISTRIBUTOR_ROLE(), distributor);
        distribution.grantRole(distribution.DISTRIBUTOR_ROLE(), address(dualDistributor));
    }

    function testStateVar() public {
        assertEq(dualDistributor.dividendDistribution(), address(distribution));
    }

    function testSetDividendDistributionZeroAddressReverts() public {
        vm.expectRevert(DualDistributor.ZeroAddress.selector);
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
        dualDistributor.setDividendDistribution(account);
        assertEq(dualDistributor.dividendDistribution(), account);
    }

    function testSetXdShareForDShareZeroAddressReverts() public {
        vm.expectRevert(DualDistributor.ZeroAddress.selector);
        dualDistributor.setXdShareForDShare(address(0), address(1));
    }

    function testSetXdShareForDShare(address _dShare, address _XdShare) public {
        vm.assume(_dShare != address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, distribution.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        dualDistributor.setXdShareForDShare(_dShare, _XdShare);

        dualDistributor.setXdShareForDShare(_dShare, _XdShare);
        assertEq(dualDistributor.dShareToXdShare(_dShare), _XdShare);
    }

    function testDistribute(uint256 amountA, uint256 amountB, uint256 endTime) public {
        vm.assume(endTime > block.timestamp + distribution.minDistributionTime());

        token.mint(address(dualDistributor), amountA);
        dtoken.mint(address(dualDistributor), amountB);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), distribution.DISTRIBUTOR_ROLE()
            )
        );
        dualDistributor.distribute(address(token), address(dtoken), amountA, amountB, endTime);

        vm.prank(distributor);
        vm.expectRevert(DualDistributor.ZeroAddress.selector);
        dualDistributor.distribute(address(token), address(dtoken), amountA, amountB, endTime);

        dualDistributor.setXdShareForDShare(address(dtoken), address(xToken));

        vm.prank(distributor);
        vm.expectRevert(DualDistributor.ZeroAddress.selector);
        dualDistributor.distribute(address(0), address(dtoken), amountA, amountB, endTime);

        vm.prank(distributor);
        vm.expectEmit(true, true, true, true);
        emit NewDistribution(0, address(dtoken), amountA, amountB);
        dualDistributor.distribute(address(token), address(dtoken), amountA, amountB, endTime);
    }
}
