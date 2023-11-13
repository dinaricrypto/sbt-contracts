// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../../src/TransferRestrictorLocked.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract TransferRestrictorLockedTest is Test {
    TransferRestrictorLocked public restrictor;

    function setUp() public {
        restrictor = new TransferRestrictorLocked();
    }

    function testIsBlacklisted(address account) public {
        assertEq(restrictor.isBlacklisted(account), true);
    }

    function testRequireNotRestricted(address account) public {
        vm.expectRevert(ITransferRestrictor.AccountRestricted.selector);
        restrictor.requireNotRestricted(account, address(0));
        vm.expectRevert(ITransferRestrictor.AccountRestricted.selector);
        restrictor.requireNotRestricted(address(0), account);
    }
}
