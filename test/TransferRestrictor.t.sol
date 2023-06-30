// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../src/TransferRestrictor.sol";

contract TransferRestrictorTest is Test {
    event Restricted(address indexed account);
    event Unrestricted(address indexed account);

    TransferRestrictor public restrictor;

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
    }

    function testRestrictUnrestrict(address account) public {
        vm.expectEmit(true, true, true, true);
        emit Restricted(account);
        restrictor.restrict(account);
        assertEq(restrictor.blacklist(account), true);

        vm.expectRevert(TransferRestrictor.AccountRestricted.selector);
        restrictor.requireNotRestricted(account, address(0));
        vm.expectRevert(TransferRestrictor.AccountRestricted.selector);
        restrictor.requireNotRestricted(address(0), account);

        vm.expectEmit(true, true, true, true);
        emit Unrestricted(account);
        restrictor.unrestrict(account);
        assertEq(restrictor.blacklist(account), false);

        restrictor.requireNotRestricted(account, address(0));
        restrictor.requireNotRestricted(address(0), account);
    }
}
