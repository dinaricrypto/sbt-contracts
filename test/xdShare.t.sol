// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {dShare} from "../src/dShare.sol";
import {xdShare} from "../src/xdShare.sol";
import {TransferRestrictor, ITransferRestrictor} from "../src/TransferRestrictor.sol";
import {TokenManager} from "../src/TokenManager.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract xdShareTest is Test {
    TransferRestrictor public restrictor;
    TokenManager tokenManager;
    dShare public token;
    xdShare public xToken;

    event VaultLocked();
    event VaultUnlocked();

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        tokenManager = new TokenManager(restrictor);
        // token = new dShare(
        //     address(this),
        //     "Dinari Token",
        //     "dTKN",
        //     "example.com",
        //     restrictor
        // );
        token = tokenManager.deployNewToken(address(this), "Dinari Token", "dTKN");
        token.grantRole(token.MINTER_ROLE(), address(this));

        xToken = new xdShare(token, tokenManager);
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

    function testLockMint(uint128 amount, address user, address receiver) public {
        vm.assume(user != address(0));
        assertEq(xToken.balanceOf(user), 0);

        token.mint(user, amount);

        vm.prank(user);
        token.approve(address(xToken), amount);

        vm.expectEmit(true, true, true, true);
        emit VaultLocked();
        xToken.lock();

        vm.prank(user);
        vm.expectRevert(xdShare.DepositsPaused.selector);
        xToken.mint(amount, receiver);

        vm.expectEmit(true, true, true, true);
        emit VaultUnlocked();
        xToken.unlock();

        vm.prank(user);
        uint256 assets = xToken.deposit(amount, receiver);

        assertEq(xToken.balanceOf(receiver), assets);
    }

    function testRedeemLock(uint128 amount, address user, address receiver) public {
        vm.assume(user != address(0));
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
        vm.expectRevert(xdShare.WithdrawalsPaused.selector);
        xToken.redeem(assets, user, receiver);

        vm.expectEmit(true, true, true, true);
        emit VaultUnlocked();
        xToken.unlock();

        vm.prank(receiver);
        xToken.redeem(assets, user, receiver);

        assertEq(xToken.balanceOf(receiver), 0);
        assertEq(token.balanceOf(user), amount);
    }

    function testLockDeposit(uint128 amount, address user) public {
        vm.assume(user != address(0));
        assertEq(xToken.balanceOf(user), 0);

        token.mint(user, amount);

        vm.prank(user);
        token.approve(address(xToken), amount);

        vm.expectEmit(true, true, true, true);
        emit VaultLocked();
        xToken.lock();

        vm.prank(user);
        vm.expectRevert(xdShare.DepositsPaused.selector);
        xToken.deposit(amount, user);

        vm.expectEmit(true, true, true, true);
        emit VaultUnlocked();
        xToken.unlock();

        vm.prank(user);
        uint256 shares = xToken.deposit(amount, user);

        assertEq(xToken.balanceOf(user), shares);
    }

    function testLockWithdrawal(uint128 amount, address user) public {
        vm.assume(user != address(0));
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
        vm.expectRevert(xdShare.WithdrawalsPaused.selector);
        xToken.withdraw(shares, user, user);

        vm.expectEmit(true, true, true, true);
        emit VaultUnlocked();
        xToken.unlock();

        vm.prank(user);
        xToken.withdraw(shares, user, user);

        assertEq(xToken.balanceOf(user), 0);
    }

    function testDepositSplit(address user, address user2, uint128 supply, uint8 multiple, bool reverse) public {
        vm.assume(user != address(0));
        vm.assume(user2 != address(0));
        // vm.assume(supply > 0);
        // vm.assume(multiple > 2);
        token.mint(user, supply);
        token.mint(user2, supply);

        // deposit and withdraw first
        vm.prank(user);
        token.approve(address(xToken), supply);

        vm.prank(user);
        xToken.deposit(supply, user);

        assertEq(token.balanceOf(address(xToken)), supply);

        // vm.prank(user);
        // xToken.withdraw(shares, user, user);

        if (supply > 0 && multiple > 2) {
            (dShare newToken,) = tokenManager.split(token, multiple, reverse);
            tokenManager.convertVaultBalance(newToken, address(xToken));
            // check if token has been burn
            assertEq(token.balanceOf(address(xToken)), 0);
            vm.assume(overflowChecker(supply, multiple));
            if (reverse) {
                assertEq(newToken.balanceOf(address(xToken)), supply / multiple);        
            } else {
                assertEq(newToken.balanceOf(address(xToken)), supply * multiple);       
            }

            // vm.prank(user);
            // token.approve(address(xToken), supply);

            // uint256 splitAmount = tokenManager.splitAmount(multiple, reverse, supply);

            

            // vm.prank(user);
            // newToken.approve(address(xToken), 2**256 -1);

            // vm.prank(user);
            // xToken.deposit(supply, user);
            // assertEq(token.balanceOf(user), 0);
            // assertEq(newToken.balanceOf(address(xToken)), splitAmount);
            // assertEq(newToken.balanceOf(user), 0);
            // assertLt(shares, share1);
            // assertEq(shares * multiple * 2, share1);
        }
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

        // check if address is blacklist
        assertEq(xToken.isBlacklisted(user), true);
        restrictor.unrestrict(user);

        vm.prank(alice);
        xToken.transfer(user, (aliceShareAmount / 2));
    }
}
