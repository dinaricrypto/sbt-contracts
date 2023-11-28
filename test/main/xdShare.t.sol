// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {DShare} from "../../src/DShare.sol";
import {XdShare} from "../../src/dividend/XDShare.sol";
import {TransferRestrictor, ITransferRestrictor} from "../../src/TransferRestrictor.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract XdShareTest is Test {
    TransferRestrictor public restrictor;
    DShare public token;
    XdShare public xToken;

    address user = address(1);
    address user2 = address(2);

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        restrictor.grantRole(restrictor.RESTRICTOR_ROLE(), address(this));
        DShare tokenImplementation = new DShare();
        token = DShare(
            address(
                new ERC1967Proxy(
                    address(tokenImplementation),
                    abi.encodeCall(DShare.initialize, (address(this), "Dinari Token", "dTKN", restrictor))
                )
            )
        );
        token.grantRole(token.MINTER_ROLE(), address(this));

        XdShare xtokenImplementation = new XdShare();
        xToken = XdShare(
            address(
                new ERC1967Proxy(
                    address(xtokenImplementation),
                    abi.encodeCall(XdShare.initialize, (token, "Reinvesting dTKN.d", "dTKN.d.x"))
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

    function testMint(uint128 amount, address receiver) public {
        vm.assume(receiver != address(this));

        assertEq(xToken.balanceOf(user), 0);

        token.mint(user, amount);

        vm.prank(user);
        token.approve(address(xToken), amount);

        vm.prank(user);
        uint256 assets = xToken.deposit(amount, receiver);

        assertEq(xToken.balanceOf(receiver), assets);
    }

    function testRedeem(uint128 amount, address receiver) public {
        vm.assume(receiver != address(this));

        assertEq(xToken.balanceOf(user), 0);

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
