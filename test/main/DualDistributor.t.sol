// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DividendDistribution} from "../../src/dividend/DividendDistribution.sol";
import {DualDistributor} from "../../src/dividend/DualDistributor.sol";
import {TransferRestrictor, ITransferRestrictor} from "../../src/TransferRestrictor.sol";
import {xdShare} from "../../src/dividend/xdShare.sol";
import {dShare} from "../../src/dShare.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract DualDistributorTest is Test {
    DividendDistribution distribution;
    DualDistributor dualDistributor;
    TransferRestrictor public restrictor;
    xdShare xToken;
    dShare dtoken;
    MockERC20 token;

    uint256 public userPrivateKey;
    uint256 public ownerPrivateKey;

    address public user = address(1);
    address public user2 = address(2);
    address public distributor = address(4);

    event NewDistribution(uint256 distributionId, address indexed dShare, uint256 usdcAmount, uint256 dShareAmount);

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        token = new MockERC20("Money", "$", 6);
        dtoken = new dShare(address(this), "Dinari Token", "dTKN", "", restrictor);
        xToken = new xdShare(dtoken, "Dinari xdToken", "xdTKN");

        dtoken.grantRole(dtoken.MINTER_ROLE(), address(this));

        distribution = new DividendDistribution(address(this));

        distribution.grantRole(distribution.DISTRIBUTOR_ROLE(), distributor);
        dualDistributor = new DualDistributor(address(this), address(token), address(distribution));
        dualDistributor.grantRole(dualDistributor.DISTRIBUTOR_ROLE(), distributor);
        distribution.grantRole(distribution.DISTRIBUTOR_ROLE(), address(dualDistributor));
    }

    function testStateVar() public {
        assertEq(dualDistributor.USDC(), address(token));
        assertEq(dualDistributor.dividendDistrubtion(), address(distribution));
    }

    function testSetter(address _newUSDC, address _dShare, address _xdShare, address _newDividend) public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, distribution.DEFAULT_ADMIN_ROLE()
            )
        );
        dualDistributor.setUSDC(_newUSDC);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, distribution.DEFAULT_ADMIN_ROLE()
            )
        );
        dualDistributor.setNewDividendAddress(_newDividend);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, distribution.DEFAULT_ADMIN_ROLE()
            )
        );
        dualDistributor.addDShareXdSharePair(_dShare, _xdShare);
        vm.stopPrank();

        if (_newUSDC == address(0)) {
            vm.expectRevert(DualDistributor.ZeroAddress.selector);
            dualDistributor.setUSDC(_newUSDC);
        } else if (_newDividend == address(0)) {
            vm.expectRevert(DualDistributor.ZeroAddress.selector);
            dualDistributor.setNewDividendAddress(_newDividend);
        } else if (_dShare == address(0)) {
            vm.expectRevert(DualDistributor.ZeroAddress.selector);
            dualDistributor.addDShareXdSharePair(_dShare, _xdShare);
        } else if (_xdShare == address(0)) {
            vm.expectRevert(DualDistributor.ZeroAddress.selector);
            dualDistributor.addDShareXdSharePair(_dShare, _xdShare);
        } else {
            dualDistributor.setUSDC(_newUSDC);
            dualDistributor.setNewDividendAddress(_newDividend);
            dualDistributor.addDShareXdSharePair(_dShare, _xdShare);

            assertEq(dualDistributor.USDC(), _newUSDC);
            assertEq(dualDistributor.dividendDistrubtion(), _newDividend);
            assertEq(dualDistributor.dShareToXdShare(_dShare), _xdShare);
        }
    }

    function testDistribute(uint256 amountA, uint256 amountB, uint256 endTime) public {
        vm.assume(endTime > block.timestamp);

        token.mint(address(dualDistributor), amountA);
        dtoken.mint(address(dualDistributor), amountB);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), distribution.DISTRIBUTOR_ROLE()
            )
        );
        dualDistributor.distribute(address(dtoken), amountA, amountB, endTime);

        vm.prank(distributor);
        vm.expectRevert(DualDistributor.ZeroAddress.selector);
        dualDistributor.distribute(address(dtoken), amountA, amountB, endTime);

        dualDistributor.addDShareXdSharePair(address(dtoken), address(xToken));

        vm.prank(distributor);
        vm.expectRevert(DualDistributor.XdshareIsNotLocked.selector);
        dualDistributor.distribute(address(dtoken), amountA, amountB, endTime);

        xToken.lock();

        vm.prank(distributor);
        vm.expectEmit(true, true, true, true);
        emit NewDistribution(0, address(dtoken), amountA, amountB);
        dualDistributor.distribute(address(dtoken), amountA, amountB, endTime);
    }
}
