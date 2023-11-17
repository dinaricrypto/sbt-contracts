// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {Vault, IVault} from "../../src/Vault.sol";
import {MockToken} from "../utils/mocks/MockToken.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract VaultTest is Test {
    Vault vault;
    address user;
    address mockAddress;

    MockToken paymentToken;
    MockToken rescueToken;

    event FundsWithdrawn(IERC20 token, address to, uint256 amount);

    function setUp() public {
        vault = new Vault(address(this));
        user = address(2);
        mockAddress = address(3);

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

    function testWithdrawFunds(address to, uint256 amount) public {
        assertEq(paymentToken.balanceOf(address(to)), 0);
        vm.assume(to != address(0));
        paymentToken.mint(address(vault), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, vault.AUTHORIZED_OPERATOR_ROLE()
            )
        );
        vm.prank(user);
        vault.withdrawFunds(paymentToken, to, amount);

        vault.grantRole(vault.AUTHORIZED_OPERATOR_ROLE(), mockAddress);

        vm.expectEmit(true, true, true, true);
        emit FundsWithdrawn(paymentToken, to, amount);
        vm.prank(mockAddress);
        vault.withdrawFunds(paymentToken, to, amount);
        assertEq(paymentToken.balanceOf(address(to)), amount);
    }
}
