// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {Vault, IVault} from "../../src/Vault.sol";
import {MockToken} from "../utils/mocks/MockToken.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract VaultTest is Test {
    Vault vault;
    address user;

    MockToken paymentToken;
    MockToken rescueToken;

    function setUp() public {
        vault = new Vault(address(this));
        user = address(2);

        paymentToken = new MockToken("Money", "$");
        rescueToken = new MockToken("RescueMoney", "$");
    }

    function testDepositInVaultAndRescue(uint256 amount) public {
        paymentToken.mint(user, amount);
        rescueToken.mint(user, amount);

        vm.prank(user);
        paymentToken.transfer(address(vault), amount);

        vm.prank(user);
        rescueToken.transfer(address(vault), amount);

        assertEq(paymentToken.balanceOf(address(vault)), amount);
        assertEq(rescueToken.balanceOf(address(vault)), amount);
        assertEq(rescueToken.balanceOf(user), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, vault.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        vault.rescueERC20(rescueToken, user, amount);

        vault.rescueERC20(rescueToken, user, amount);

        assertEq(rescueToken.balanceOf(user), amount);
    }
}
