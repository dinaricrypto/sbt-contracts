// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../src/TransferRestrictor.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract TransferRestrictorTest is Test {
    event Restricted(address indexed account);
    event Unrestricted(address indexed account);

    TransferRestrictor public restrictor;
    address public restrictor_role = address(1);

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        restrictor.grantRole(restrictor.RESTRICTOR_ROLE(), restrictor_role);
    }

    function accessErrorString(address account, bytes32 role) internal pure returns (bytes memory) {
        return bytes.concat(
            "AccessControl: account ",
            bytes(Strings.toHexString(account)),
            " is missing role ",
            bytes(Strings.toHexString(uint256(role), 32))
        );
    }

    function testInvalidRoleAccess(address account) public {
        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(address(this)),
                    " is missing role ",
                    Strings.toHexString(uint256(restrictor.RESTRICTOR_ROLE()), 32)
                )
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
