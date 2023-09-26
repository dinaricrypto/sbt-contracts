// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";
import {DualDistributor} from "../src/dividend/DualDistributor.sol";
import {TransferRestrictor, ITransferRestrictor} from "../src/TransferRestrictor.sol";
import {xdShare} from "../src/xdShare.sol";
import {dShare} from "../src/dShare.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

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

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        token = new MockERC20("Money", "$", 6);
        dtoken = new dShare(
            address(this),
            "Dinari Token",
            "dTKN",
            "example.com",
            restrictor
        );
        xToken = new xdShare(dtoken);

        distribution = new DividendDistribution(address(this));

        distribution.grantRole(distribution.DISTRIBUTOR_ROLE(), distributor);

        dualDistributor = new DualDistributor(address(this), address(token), address(distribution));
        dualDistributor.grantRole(dualDistributor.DISTRIBUTOR_ROLE(), distributor);
    }

    function accessErrorString(address account, bytes32 role) internal pure returns (bytes memory) {
        return bytes.concat(
            "AccessControl: account ",
            bytes(Strings.toHexString(account)),
            " is missing role ",
            bytes(Strings.toHexString(uint256(role), 32))
        );
    }

    function testStateVar() public {
        assertEq(dualDistributor.USDC(), address(token));
        assertEq(dualDistributor.dividendDistrubtion(), address(distribution));
    }

    function testSetter(address _newUSDC, address _dShare, address _xdShare, address _newDividend) public {
        vm.startPrank(user);
        vm.expectRevert(accessErrorString(user, distribution.DISTRIBUTOR_ROLE()));
        dualDistributor.setUSDC(_newUSDC);
        vm.expectRevert(accessErrorString(user, distribution.DISTRIBUTOR_ROLE()));
        dualDistributor.setNewDividendAddress(_newDividend);
        vm.expectRevert(accessErrorString(user, distribution.DISTRIBUTOR_ROLE()));
        dualDistributor.addDShareXdSharePair(_dShare, _xdShare);
        vm.stopPrank();

        vm.startPrank(distributor);

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

        vm.stopPrank();
    }

    function testDistribute(uint256 amountA, uint256 amountB) public {
        token.mint(address(dualDistributor), amountA);
        dtoken.mint(address(dualDistributor), amountB);
        xToken.lock();

        vm.expectRevert(accessErrorString(address(this), distribution.DISTRIBUTOR_ROLE()));
        dualDistributor.distribute(address(dtoken), amountA, amountB);

        vm.prank(distributor);
        vm.expectRevert(DualDistributor.InvalidxDshare.selector);
        dualDistributor.distribute(address(dtoken), amountA, amountB);

        vm.prank(distributor);
        dualDistributor.addDShareXdSharePair(address(dtoken), address(xToken));

        vm.prank(distributor);
        vm.expectRevert(DualDistributor.XdshareIsLocked.selector);
        dualDistributor.distribute(address(dtoken), amountA, amountB);

        xToken.unlock();

        vm.prank(distributor);
        dualDistributor.distribute(address(dtoken), amountA, amountB);
    }
}
