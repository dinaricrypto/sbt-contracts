// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../src/TransferRestrictor.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TransferRestrictorTest is Test {
    event Restricted(address indexed account);
    event Unrestricted(address indexed account);

    TransferRestrictor public restrictor;
    address public restrictor_role = address(1);
    address public admin = address(2);
    address public upgrader = address(3);

    function setUp() public {
        vm.startPrank(admin);
        TransferRestrictor restrictorImpl = new TransferRestrictor();
        restrictor = TransferRestrictor(
            address(
                new ERC1967Proxy(address(restrictorImpl), abi.encodeCall(restrictorImpl.initialize, (admin, upgrader)))
            )
        );
        restrictor.grantRole(restrictor.RESTRICTOR_ROLE(), restrictor_role);
        vm.stopPrank();
    }

    function testInvalidRoleAccess(address account) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), restrictor.RESTRICTOR_ROLE()
            )
        );
        restrictor.restrict(account);

        vm.prank(restrictor_role);
        restrictor.restrict(account);
    }

    function testRestrictUnrestrict(address account) public {
        vm.startPrank(restrictor_role);
        vm.expectEmit(true, true, true, true);
        emit Restricted(account);
        restrictor.restrict(account);
        assertEq(restrictor.isBlacklisted(account), true);

        vm.expectRevert(TransferRestrictor.AccountRestricted.selector);
        restrictor.requireNotRestricted(account, address(0));
        vm.expectRevert(TransferRestrictor.AccountRestricted.selector);
        restrictor.requireNotRestricted(address(0), account);

        vm.expectEmit(true, true, true, true);
        emit Unrestricted(account);
        restrictor.unrestrict(account);
        assertEq(restrictor.isBlacklisted(account), false);

        restrictor.requireNotRestricted(account, address(0));
        restrictor.requireNotRestricted(address(0), account);
        vm.stopPrank();
    }
}
