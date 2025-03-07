// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {Vault, IVault} from "../src/orders/Vault.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract VaultTest is Test {
    Vault vault;
    address user;
    address admin;
    address upgrader;
    address mockAddress;

    MockToken paymentToken;
    MockToken rescueToken;

    event FundsWithdrawn(IERC20 token, address to, uint256 amount);

    function setUp() public {
        user = address(2);
        mockAddress = address(3);
        admin = address(4);
        upgrader = address(5);

        Vault vaultImpl = new Vault();
        vault = Vault(
            address(new ERC1967Proxy(address(vaultImpl), abi.encodeCall(vaultImpl.initialize, (admin, upgrader))))
        );

        vm.startPrank(admin);
        paymentToken = new MockToken("Money", "$");
        rescueToken = new MockToken("RescueMoney", "$");
        vm.stopPrank();
    }

    function testDepositInVaultAndRescue(uint256 amount) public {
        vm.startPrank(admin);
        paymentToken.mint(user, amount);
        rescueToken.mint(user, amount);
        vm.stopPrank();

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

        vm.prank(admin);
        vault.rescueERC20(rescueToken, user, amount);

        assertEq(rescueToken.balanceOf(user), amount);
    }

    function testWithdrawFunds(address to, uint256 amount) public {
        assertEq(paymentToken.balanceOf(address(to)), 0);
        vm.assume(to != address(0));

        vm.prank(admin);
        paymentToken.mint(address(vault), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, vault.OPERATOR_ROLE()
            )
        );
        vm.prank(user);
        vault.withdrawFunds(paymentToken, to, amount);

        vm.startPrank(admin);
        vault.grantRole(vault.OPERATOR_ROLE(), mockAddress);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit FundsWithdrawn(paymentToken, to, amount);
        vm.startPrank(mockAddress);
        vault.withdrawFunds(paymentToken, to, amount);
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(to)), amount);
    }
}
