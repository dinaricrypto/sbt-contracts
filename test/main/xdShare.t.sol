// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {dShare} from "../../src/dShare.sol";
import {xdShare} from "../../src/dividend/xdShare.sol";
import {TransferRestrictor, ITransferRestrictor} from "../../src/TransferRestrictor.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NumberUtils} from "../../src/common/NumberUtils.sol";
import {mulDiv, mulDiv18} from "prb-math/Common.sol";

contract xdShareTest is Test {
    TransferRestrictor public restrictor;
    dShare public token;
    xdShare public xToken;

    event VaultLocked();
    event VaultUnlocked();

    address user = address(1);
    address user2 = address(2);

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        restrictor.grantRole(restrictor.RESTRICTOR_ROLE(), address(this));
        dShare tokenImplementation = new dShare();
        token = dShare(
            address(
                new ERC1967Proxy(
                address(tokenImplementation),
                abi.encodeCall(dShare.initialize, (address(this), "Dinari Token", "dTKN", restrictor))
                )
            )
        );
        token.grantRole(token.MINTER_ROLE(), address(this));

        xdShare xtokenImplementation = new xdShare();
        xToken = xdShare(
            address(
                new ERC1967Proxy(
                address(xtokenImplementation),
                abi.encodeCall(xdShare.initialize, (token, "Reinvesting dTKN.d", "dTKN.d.x"))
                )
            )
        );
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
        vm.assume(receiver != address(this));

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
        vm.assume(receiver != address(this));

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

    function testDepositRebaseRedeem(uint128 supply, uint128 balancePerShare) public {
        vm.assume(supply > 0);
        vm.assume(balancePerShare > 0);
        vm.assume(!NumberUtils.mulDivCheckOverflow(supply, 1 ether, balancePerShare));
        vm.assume(!NumberUtils.mulDivCheckOverflow(supply, balancePerShare, 1 ether));

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
        token.setBalancePerShare(balancePerShare);

        // console.log("user assets in vault after conversion", xToken.convertToAssets(xToken.balanceOf(user)));

        // user redeem
        vm.startPrank(user);
        uint256 shares = xToken.balanceOf(user);
        xToken.redeem(shares, user, user);
        vm.stopPrank();

        // conversion in vault should be within 1 share's worth of standard conversion
        uint256 userBalance = token.balanceOf(user);
        if (userBalance > 0) {
            uint256 oneShareInAssets = xToken.convertToAssets(1);
            assertGe(userBalance, token.balanceOf(user2) - oneShareInAssets);
        }
    }

    function testDepositYieldRebaseYieldRedeem() public {
        uint128 amount = 1000;
        uint128 balancePerShare = 42 ether;
        // vm.assume(amount > 0);
        // vm.assume(balancePerShare > 0);
        // vm.assume(!NumberUtils.mulDivCheckOverflow(amount, 1 ether, balancePerShare));
        // vm.assume(!NumberUtils.mulDivCheckOverflow(amount, balancePerShare, 1 ether));

        // deposit pre-existing amount
        token.mint(address(this), 1 ether);
        token.approve(address(xToken), 1 ether);
        xToken.deposit(1 ether, address(this));

        // user deposit
        token.mint(user, amount);
        assertEq(xToken.balanceOf(user), 0);

        vm.startPrank(user);
        token.approve(address(xToken), amount);
        xToken.deposit(amount, user);
        vm.stopPrank();
        assertEq(xToken.balanceOf(user), amount);

        // yield 1%
        uint256 onePercent = token.totalSupply() / 100;
        token.mint(address(xToken), onePercent);
        console.log("max withdraw", xToken.maxWithdraw(user));
        uint256 yield1 = amount / 100;
        console.log("one percent", onePercent);
        console.log("yield1", yield1);
        assertEq(xToken.maxWithdraw(user), amount + (yield1 > 0 ? yield1 - 1 : 0));

        // rebase
        token.setBalancePerShare(balancePerShare);
        uint256 rebasedOnePercent = mulDiv18(onePercent, balancePerShare);
        uint256 rebasedAmount = mulDiv18(amount, balancePerShare);
        if (yield1 > 0) {
            yield1 = mulDiv18(yield1, balancePerShare);
        }
        // yield1 = mulDiv18(yield1, balancePerShare);
        uint256 oneShareInAssets = xToken.convertToAssets(1);
        console.log("max withdraw", xToken.maxWithdraw(user));
        console.log("rebased one percent", rebasedOnePercent);
        console.log("rebased amount", rebasedAmount);
        console.log("yield1", yield1);
        console.log("one share in assets", oneShareInAssets);
        if (rebasedAmount > 0) {
            assertEq(xToken.maxWithdraw(user), rebasedAmount - 1 + yield1);
        }
        // assertEq(xToken.maxWithdraw(user), rebasedAmount - (oneShareInAssets > 0 ? oneShareInAssets - 1 : 0)); // (yield1 > 0 ? yield1 - 1 : 0)); // (yield1 > 0 ? yield1 - oneShareInAssets + 1 : 0));

        // yield 1%
        uint256 yield2 = rebasedAmount / 100;
        token.mint(address(xToken), rebasedOnePercent);
        console.log("max withdraw", xToken.maxWithdraw(user));

        // user redeem
        vm.startPrank(user);
        uint256 shares = xToken.balanceOf(user);
        xToken.redeem(shares, user, user);
        vm.stopPrank();

        // vault should capture rebase and yield
        uint256 userBalance = token.balanceOf(user);
        if (userBalance > 0) {
            console.log("user balance", userBalance);
            console.log("yield2", yield2);
            assertGe(token.balanceOf(user), rebasedAmount - oneShareInAssets + yield1 + yield2);
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
        assertEq(xToken.isBlacklisted(user), true);

        vm.prank(alice);
        vm.expectRevert(TransferRestrictor.AccountRestricted.selector);
        xToken.transfer(user, amount);

        // remove restrictor
        token.setTransferRestrictor(ITransferRestrictor(address(0)));
        assertEq(xToken.isBlacklisted(user), false);

        vm.prank(alice);
        xToken.transfer(user, (aliceShareAmount / 2));
    }
}
