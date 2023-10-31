// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {dShare} from "../../src/dShare.sol";
import {xdShare} from "../../src/dividend/xdShare.sol";
import {TransferRestrictor, ITransferRestrictor} from "../../src/TransferRestrictor.sol";
import {dShareManager} from "../../src/dShareManager.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract xdShareTest is Test {
    TransferRestrictor public restrictor;
    dShareManager tokenManager;
    dShare public token;
    xdShare public xToken;

    event VaultLocked();
    event VaultUnlocked();

    address user = address(1);
    address user2 = address(2);

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        restrictor.grantRole(restrictor.RESTRICTOR_ROLE(), address(this));
        tokenManager = new dShareManager(restrictor);
        token = tokenManager.deployNewToken(address(this), "Dinari Token", "dTKN");
        token.grantRole(token.MINTER_ROLE(), address(this));

        xToken = new xdShare(token, tokenManager, "Reinvesting dTKN.d", "dTKN.d.x");
    }

    function overflowChecker(uint256 a, uint256 b) internal pure returns (bool) {
        if (a == 0 || b == 0) {
            return false;
        }
        uint256 c;
        unchecked {
            c = a * b;
        }
        return c / a != b;
    }

    function testMetadata() public {
        assertEq(xToken.name(), "Reinvesting dTKN.d");
        assertEq(xToken.symbol(), "dTKN.d.x");
        assertEq(xToken.decimals(), 18);
        assertEq(xToken.asset(), address(token));
    }

    function testLockMint(uint128 amount, address receiver) public {
        assertEq(xToken.balanceOf(user), 0);

        token.mint(user, amount);

        vm.prank(user);
        token.approve(address(xToken), amount);

        vm.expectEmit(true, true, true, true);
        emit VaultLocked();
        xToken.lock();

        vm.prank(user);
        vm.expectRevert(xdShare.IssuancePaused.selector);
        xToken.mint(amount, receiver);

        vm.expectEmit(true, true, true, true);
        emit VaultUnlocked();
        xToken.unlock();

        vm.prank(user);
        uint256 assets = xToken.deposit(amount, receiver);

        assertEq(xToken.balanceOf(receiver), assets);
    }

    function testRedeemLock(uint128 amount, address receiver) public {
        assertEq(xToken.balanceOf(user), 0);

        token.mint(user, amount);

        vm.prank(user);
        token.approve(address(xToken), amount);

        vm.prank(user);
        uint256 assets = xToken.mint(amount, receiver);
        assertEq(token.balanceOf(user), 0);

        vm.expectEmit(true, true, true, true);
        emit VaultLocked();
        xToken.lock();

        vm.prank(receiver);
        vm.expectRevert(xdShare.IssuancePaused.selector);
        xToken.redeem(assets, user, receiver);

        vm.expectEmit(true, true, true, true);
        emit VaultUnlocked();
        xToken.unlock();

        vm.prank(receiver);
        xToken.redeem(assets, user, receiver);

        assertEq(xToken.balanceOf(receiver), 0);
        assertEq(token.balanceOf(user), amount);
    }

    function testLockDeposit(uint128 amount) public {
        assertEq(xToken.balanceOf(user), 0);

        token.mint(user, amount);

        vm.prank(user);
        token.approve(address(xToken), amount);

        vm.expectEmit(true, true, true, true);
        emit VaultLocked();
        xToken.lock();

        vm.prank(user);
        vm.expectRevert(xdShare.IssuancePaused.selector);
        xToken.deposit(amount, user);

        vm.expectEmit(true, true, true, true);
        emit VaultUnlocked();
        xToken.unlock();

        vm.prank(user);
        uint256 shares = xToken.deposit(amount, user);

        assertEq(xToken.balanceOf(user), shares);
    }

    function testLockWithdrawal(uint128 amount) public {
        vm.assume(amount > 0);
        assertEq(xToken.balanceOf(user), 0);

        token.mint(user, amount);
        uint256 balanceBefore = token.balanceOf(user);
        assertEq(balanceBefore, amount);

        vm.prank(user);
        token.approve(address(xToken), amount);

        vm.prank(user);
        uint256 shares = xToken.deposit(amount, user);
        assertEq(xToken.balanceOf(user), shares);
        assertEq(token.balanceOf(user), 0);

        vm.expectEmit(true, true, true, true);
        emit VaultLocked();
        xToken.lock();

        vm.prank(user);
        vm.expectRevert(xdShare.IssuancePaused.selector);
        xToken.withdraw(shares, user, user);

        vm.expectEmit(true, true, true, true);
        emit VaultUnlocked();
        xToken.unlock();

        vm.prank(user);
        xToken.withdraw(shares, user, user);

        assertEq(xToken.balanceOf(user), 0);
        assertEq(token.balanceOf(address(xToken)), 0);
    }

    function testDepositRedeemSplit(uint128 supply, uint8 multiple, bool reverse) public {
        vm.assume(supply > 1);
        vm.assume(multiple > 2);

        // user: mint -> deposit -> split -> withdraw
        token.mint(user, supply);
        // user2: mint -> split -> convert
        token.mint(user2, supply);

        assertEq(xToken.balanceOf(user), 0);
        assertEq(xToken.balanceOf(user2), 0);

        // user deposit
        vm.startPrank(user);
        token.approve(address(xToken), supply);
        xToken.deposit(supply, user);
        vm.stopPrank();
        assertEq(xToken.balanceOf(user), supply);

        // split
        (dShare newToken,) = tokenManager.split(token, multiple, reverse, "old", "old");

        // user2 convert
        vm.startPrank(user2);
        token.approve(address(tokenManager), supply);
        tokenManager.convert(token, supply);
        vm.stopPrank();

        // user redeem reverts
        vm.startPrank(user);
        uint256 shares = xToken.balanceOf(user);
        xToken.approve(address(xToken), shares);

        vm.expectRevert(xdShare.SplitConversionNeeded.selector);
        xToken.redeem(shares, user, user);
        vm.stopPrank();

        // check vault balances before conversion
        console.log("supply", supply);
        console.log("user assets in vault", xToken.convertToAssets(xToken.balanceOf(user)));
        assertEq(xToken.convertToAssets(xToken.balanceOf(user)), supply);

        // convert vault assets
        xToken.convertVaultBalance();

        console.log("user assets in vault after conversion", xToken.convertToAssets(xToken.balanceOf(user)));

        // user redeem
        vm.startPrank(user);
        shares = xToken.balanceOf(user);
        xToken.approve(address(xToken), shares);
        xToken.redeem(shares, user, user);
        vm.stopPrank();

        // conversion in vault should be within 1 share's worth of standard conversion
        uint256 userBalance = newToken.balanceOf(user);
        if (userBalance > 0) {
            uint256 oneShareInAssets = xToken.convertToAssets(1);
            assertGt(userBalance, newToken.balanceOf(user2) - oneShareInAssets);
        }
    }

    function testConvertVault(uint128 supply, uint8 multiple, bool reverse) public {
        vm.assume(supply > 6);
        vm.assume(multiple > 2);

        // user: mint -> deposit -> split -> withdraw
        token.mint(user, supply);

        vm.startPrank(user);
        token.approve(address(xToken), supply);
        xToken.deposit(supply, user);
        vm.stopPrank();
        assertEq(xToken.balanceOf(user), supply);

        vm.expectRevert(xdShare.ConversionCurrent.selector);
        xToken.convertVaultBalance();

        tokenManager.split(token, multiple, reverse, "old", "old");
        xToken.convertVaultBalance();
    }

    function testSweepConvert(uint128 supply, uint8 multiple, bool reverse) public {
        vm.assume(supply > 6);
        vm.assume(multiple > 2);

        // user: mint -> deposit -> split -> withdraw
        token.mint(user, supply);
        token.mint(user2, supply);

        vm.startPrank(user);
        token.approve(address(xToken), supply);
        xToken.deposit(supply, user);
        vm.stopPrank();
        assertEq(xToken.balanceOf(user), supply);

        // split old token
        (dShare newToken,) = tokenManager.split(token, multiple, reverse, "old", "old");

        // let convert vault token
        xToken.convertVaultBalance();
        assertEq(token.balanceOf(address(xToken)), 0);

        // transfer to pre-split token to vault
        vm.prank(user2);
        token.transfer(address(xToken), supply);

        assertEq(token.balanceOf(address(xToken)), supply);

        // lock vault
        xToken.lock();

        // sweep token
        vm.expectRevert(xdShare.IssuancePaused.selector);
        xToken.sweepConvert(token);

        xToken.unlock();

        (dShare newToken2,) = tokenManager.split(newToken, multiple, reverse, "old", "old");

        vm.expectRevert(xdShare.SplitConversionNeeded.selector);
        xToken.sweepConvert(token);

        xToken.convertVaultBalance();
        uint256 newTokenBalanceVault1 = newToken2.balanceOf(address(newToken2));

        xToken.sweepConvert(token);
        assertEq(token.balanceOf(address(xToken)), 0);
        uint256 newTokenBalanceVault2 = newToken2.balanceOf(address(xToken));

        if (newTokenBalanceVault1 > 0 && newTokenBalanceVault1 > 0) {
            assertLt(newTokenBalanceVault1, newTokenBalanceVault2);
        }
    }

    function testTransferRestrictedToReverts(uint128 amount) public {
        vm.assume(amount > 0);

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

        // check if address is blacklist
        assertEq(xToken.isBlacklisted(user), true);
        restrictor.unrestrict(user);

        vm.prank(alice);
        xToken.transfer(user, (aliceShareAmount / 2));
    }
}
