// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {DShare} from "../src/DShare.sol";
import {WrappedDShare} from "../src/WrappedDShare.sol";
import {TransferRestrictor, ITransferRestrictor} from "../src/TransferRestrictor.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NumberUtils} from "../src/common/NumberUtils.sol";
import {mulDiv, mulDiv18} from "prb-math/Common.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract WrappedDShareTest is Test {
    event NameSet(string name);
    event SymbolSet(string symbol);
    event Recovered(address indexed account, uint256 amount);

    TransferRestrictor public restrictor;
    DShare public token;
    WrappedDShare public xToken;

    address user = address(1);
    address user2 = address(2);
    address admin = address(3);
    address upgrader = address(4);

    function setUp() public {
        vm.startPrank(admin);
        TransferRestrictor restrictorImpl = new TransferRestrictor();
        restrictor = TransferRestrictor(
            address(
                new ERC1967Proxy(
                    address(restrictorImpl), abi.encodeCall(TransferRestrictor.initialize, (admin, upgrader))
                )
            )
        );
        restrictor.grantRole(restrictor.RESTRICTOR_ROLE(), admin);
        DShare tokenImplementation = new DShare();
        token = DShare(
            address(
                new ERC1967Proxy(
                    address(tokenImplementation),
                    abi.encodeCall(DShare.initialize, (admin, "Dinari Token", "dTKN", restrictor))
                )
            )
        );
        token.grantRole(token.MINTER_ROLE(), admin);

        WrappedDShare xtokenImplementation = new WrappedDShare();
        xToken = WrappedDShare(
            address(
                new ERC1967Proxy(
                    address(xtokenImplementation),
                    abi.encodeCall(WrappedDShare.initialize, (admin, token, "Reinvesting dTKN.d", "dTKN.d.x"))
                )
            )
        );

        vm.stopPrank();
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

    function testSetName(string memory name) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), xToken.DEFAULT_ADMIN_ROLE()
            )
        );
        xToken.setName(name);
        vm.expectEmit(true, true, true, true);
        emit NameSet(name);
        vm.prank(admin);
        xToken.setName(name);
        assertEq(xToken.name(), name);
    }

    function testSetSymbol(string memory symbol) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), xToken.DEFAULT_ADMIN_ROLE()
            )
        );
        xToken.setSymbol(symbol);
        vm.expectEmit(true, true, true, true);
        emit SymbolSet(symbol);
        vm.prank(admin);
        xToken.setSymbol(symbol);
        assertEq(xToken.symbol(), symbol);
    }

    function testMint(uint128 amount, address receiver) public {
        vm.assume(receiver != admin);

        assertEq(xToken.balanceOf(user), 0);

        vm.prank(admin);
        token.mint(user, amount);

        vm.prank(user);
        token.approve(address(xToken), amount);

        vm.prank(user);
        uint256 assets = xToken.deposit(amount, receiver);

        assertEq(xToken.balanceOf(receiver), assets);
    }

    function testRedeem(uint128 amount, address receiver) public {
        vm.assume(receiver != admin);

        assertEq(xToken.balanceOf(user), 0);

        vm.prank(admin);
        token.mint(user, amount);

        vm.prank(user);
        token.approve(address(xToken), amount);

        vm.prank(user);
        uint256 assets = xToken.mint(amount, receiver);
        assertEq(token.balanceOf(user), 0);

        vm.prank(receiver);
        xToken.redeem(assets, user, receiver);

        assertEq(xToken.balanceOf(receiver), 0);
        assertEq(token.balanceOf(user), amount);
    }

    function testDeposit(uint128 amount) public {
        assertEq(xToken.balanceOf(user), 0);

        vm.prank(admin);
        token.mint(user, amount);

        vm.prank(user);
        token.approve(address(xToken), amount);

        vm.prank(user);
        uint256 shares = xToken.deposit(amount, user);

        assertEq(xToken.balanceOf(user), shares);
    }

    function testWithdrawal(uint128 amount) public {
        vm.assume(amount > 0);
        assertEq(xToken.balanceOf(user), 0);

        vm.prank(admin);
        token.mint(user, amount);
        uint256 balanceBefore = token.balanceOf(user);
        assertEq(balanceBefore, amount);

        vm.prank(user);
        token.approve(address(xToken), amount);

        vm.prank(user);
        uint256 shares = xToken.deposit(amount, user);
        assertEq(xToken.balanceOf(user), shares);
        assertEq(token.balanceOf(user), 0);

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

        vm.startPrank(admin);
        // user: mint -> deposit -> split -> withdraw
        token.mint(user, supply);
        // user2: mint -> split -> convert
        token.mint(user2, supply);
        vm.stopPrank();

        assertEq(xToken.balanceOf(user), 0);
        assertEq(xToken.balanceOf(user2), 0);

        // user deposit
        vm.startPrank(user);
        token.approve(address(xToken), supply);
        xToken.deposit(supply, user);
        vm.stopPrank();
        assertEq(xToken.balanceOf(user), supply);

        // split
        vm.prank(admin);
        token.setBalancePerShare(balancePerShare);

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

    // TODO: fuzz - meaningful assert cases proved diffucult to create
    function testDepositYieldRebaseYieldRedeem() public {
        uint128 amount = 1000;
        uint128 balancePerShare = 42 ether;

        // deposit pre-existing amount
        vm.startPrank(admin);
        token.mint(admin, 1 ether);
        token.approve(address(xToken), 1 ether);
        xToken.deposit(1 ether, admin);
        vm.stopPrank();

        // user deposit
        vm.prank(admin);
        token.mint(user, amount);
        assertEq(xToken.balanceOf(user), 0);

        vm.startPrank(user);
        token.approve(address(xToken), amount);
        xToken.deposit(amount, user);
        vm.stopPrank();
        assertEq(xToken.balanceOf(user), amount);

        // yield 1%
        uint256 onePercent = token.totalSupply() / 100;
        vm.prank(admin);
        token.mint(address(xToken), onePercent);
        console.log("max withdraw", xToken.maxWithdraw(user));
        uint256 yield1 = amount / 100;
        console.log("one percent", onePercent);
        console.log("yield1", yield1);
        assertEq(xToken.maxWithdraw(user), amount + (yield1 > 0 ? yield1 - 1 : 0));

        // rebase
        vm.prank(admin);
        token.setBalancePerShare(balancePerShare);
        uint256 rebasedOnePercent = mulDiv18(onePercent, balancePerShare);
        uint256 rebasedAmount = mulDiv18(amount, balancePerShare);
        if (yield1 > 0) {
            yield1 = mulDiv18(yield1, balancePerShare);
        }
        uint256 oneShareInAssets = xToken.convertToAssets(1);
        console.log("max withdraw", xToken.maxWithdraw(user));
        console.log("rebased one percent", rebasedOnePercent);
        console.log("rebased amount", rebasedAmount);
        console.log("yield1", yield1);
        console.log("one share in assets", oneShareInAssets);
        if (rebasedAmount > 0) {
            assertEq(xToken.maxWithdraw(user), rebasedAmount - 1 + yield1);
        }

        // yield 1%
        uint256 yield2 = rebasedAmount / 100;
        vm.prank(admin);
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

        vm.prank(admin);
        token.mint(alice, aliceShareAmount);

        vm.prank(alice);
        token.approve(address(xToken), aliceShareAmount);
        assertEq(token.allowance(alice, address(xToken)), aliceShareAmount);

        vm.prank(alice);
        xToken.mint(aliceShareAmount, alice);

        vm.prank(admin);
        restrictor.restrict(user);
        assertEq(xToken.isBlacklisted(user), true);

        vm.prank(alice);
        vm.expectRevert(TransferRestrictor.AccountRestricted.selector);
        xToken.transfer(user, amount);

        // remove restrictor
        vm.prank(admin);
        token.setTransferRestrictor(ITransferRestrictor(address(0)));
        assertEq(xToken.isBlacklisted(user), false);

        vm.prank(alice);
        xToken.transfer(user, (aliceShareAmount / 2));
    }

    function testRecover(uint256 amount) public {
        vm.assume(amount > 0);

        vm.prank(admin);
        token.mint(address(xToken), amount);
        assertEq(token.balanceOf(address(xToken)), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), xToken.DEFAULT_ADMIN_ROLE()
            )
        );
        xToken.recover(user, amount);

        vm.expectEmit(true, true, true, true);
        emit Recovered(user, amount);
        vm.prank(admin);
        xToken.recover(user, amount);
        assertEq(token.balanceOf(user), amount);
    }
}
