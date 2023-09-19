// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {dShare} from "../src/dShare.sol";
import {xdShare} from "../src/xdShare.sol";
import {TransferRestrictor, ITransferRestrictor} from "../src/TransferRestrictor.sol";
import {ERC4626} from "../src/xERC4626.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract xdShareTest is Test {
    TransferRestrictor public restrictor;
    dShare public token;
    xdShare public xToken;

    error TransferFailed();

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        token = new dShare(
            address(this),
            "Dinari Token",
            "dTKN",
            "example.com",
            restrictor
        );

        xToken = new xdShare(token, 1000);
    }

    function testMetadata() public {
        assertEq(xToken.name(), "Reinvesting dTKN");
        assertEq(xToken.symbol(), "dTKN.x");
        assertEq(xToken.decimals(), 18);
        assertEq(xToken.asset(), address(token));
    }

    function testSingleMintRedeem(uint128 amount) public {
        if (amount == 0) amount = 1;

        uint256 aliceShareAmount = amount;

        address alice = address(0xABCD);

        token.mint(alice, aliceShareAmount);

        vm.prank(alice);
        token.approve(address(xToken), aliceShareAmount);
        assertEq(token.allowance(alice, address(xToken)), aliceShareAmount);

        uint256 alicePreDepositBal = token.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceUnderlyingAmount = xToken.mint(aliceShareAmount, alice);

        // Expect exchange rate to be 1:1 on initial mint.
        assertEq(aliceShareAmount, aliceUnderlyingAmount);
        assertEq(xToken.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
        assertEq(xToken.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
        assertEq(xToken.totalSupply(), aliceShareAmount);
        assertEq(xToken.totalAssets(), aliceUnderlyingAmount);
        assertEq(xToken.balanceOf(alice), aliceUnderlyingAmount);
        assertEq(xToken.convertToAssets(xToken.balanceOf(alice)), aliceUnderlyingAmount);
        assertEq(token.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);

        vm.prank(alice);
        xToken.redeem(aliceShareAmount, alice, alice);

        assertEq(xToken.totalAssets(), 0);
        assertEq(xToken.balanceOf(alice), 0);
        assertEq(xToken.convertToAssets(xToken.balanceOf(alice)), 0);
        assertEq(token.balanceOf(alice), alicePreDepositBal);
    }

    function testWithdrawWithNotEnoughUnderlyingAmountReverts() public {
        token.mint(address(this), 0.5e18);
        token.approve(address(xToken), 0.5e18);

        xToken.deposit(0.5e18, address(this));

        vm.expectRevert(ERC4626.WithdrawMoreThanMax.selector);
        xToken.withdraw(1e18, address(this), address(this));
    }

    function testMintZero() public {
        xToken.mint(0, address(this));

        assertEq(xToken.balanceOf(address(this)), 0);
        assertEq(xToken.convertToAssets(xToken.balanceOf(address(this))), 0);
        assertEq(xToken.totalSupply(), 0);
        assertEq(xToken.totalAssets(), 0);
    }

    function testTransferRestrictedToReverts(uint128 amount, address user) public {
        if (amount == 0) amount = 1;
        vm.assume(user != address(0));

        uint256 aliceShareAmount = amount;

        address alice = address(0xABCD);

        token.mint(alice, aliceShareAmount);

        vm.prank(alice);
        token.approve(address(xToken), aliceShareAmount);
        assertEq(token.allowance(alice, address(xToken)), aliceShareAmount);

        vm.prank(alice);
        xToken.mint(aliceShareAmount, alice);

        restrictor.restrict(user);

        vm.prank(alice);
        vm.expectRevert(TransferRestrictor.AccountRestricted.selector);
        xToken.transfer(user, amount);

        vm.prank(alice);
        // transfer will failed first accountRestricted - second TransferFailed from ERC20 error
        vm.expectRevert(TransferFailed.selector);
        xToken.redeem(aliceShareAmount, user, alice);

        // check if address is blacklist
        assertEq(xToken.isBlacklisted(user), true);

        // unrestrict user
        restrictor.unrestrict(user);
        vm.prank(alice);
        xToken.redeem((aliceShareAmount / 2), user, alice);

        vm.prank(alice);
        xToken.transfer(user, (aliceShareAmount / 2));
    }
}
