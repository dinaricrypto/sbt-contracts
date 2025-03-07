// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {DShare} from "../src/DShare.sol";
import {TransferRestrictor, ITransferRestrictor} from "../src/TransferRestrictor.sol";
import {
    IAccessControlDefaultAdminRules,
    IAccessControl
} from "openzeppelin-contracts/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {PRBMath_MulDiv18_Overflow, PRBMath_MulDiv_Overflow} from "prb-math/Common.sol";
import {NumberUtils} from "../src/common/NumberUtils.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

contract DShareTest is Test {
    event NameSet(string name);
    event SymbolSet(string symbol);
    event TransferRestrictorSet(ITransferRestrictor indexed transferRestrictor);
    event BalancePerShareSet(uint256 balancePerShare);

    TransferRestrictor restrictor;
    DShare token;
    address restrictor_role = address(1);
    address user = address(2);
    address admin = address(3);
    address upgrader = address(4);

    function checkMintOverFlow(uint256 toMint, uint128 balancePerShare) private returns (bool) {
        return NumberUtils.mulDivCheckOverflow(toMint, 1 ether, balancePerShare)
            || NumberUtils.mulDivCheckOverflow(toMint, balancePerShare, 1 ether)
            || (
                balancePerShare > 1 ether
                    && FixedPointMathLib.fullMulDiv(toMint, balancePerShare, 1 ether)
                        > FixedPointMathLib.fullMulDiv(type(uint256).max, 1 ether, balancePerShare)
            );
    }

    function setUp() public {
        vm.prank(admin);
        TransferRestrictor restrictorImplementation = new TransferRestrictor();
        restrictor = TransferRestrictor(
            address(
                new ERC1967Proxy(
                    address(restrictorImplementation),
                    abi.encodeCall(TransferRestrictor.initialize, (address(this), upgrader))
                )
            )
        );
        DShare tokenImplementation = new DShare();
        token = DShare(
            address(
                new ERC1967Proxy(
                    address(tokenImplementation),
                    abi.encodeCall(DShare.initialize, (address(this), "Dinari Token", "dTKN", restrictor))
                )
            )
        );
        restrictor.grantRole(restrictor.RESTRICTOR_ROLE(), restrictor_role);
    }

    function testSetName(string calldata name) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        token.setName(name);

        vm.expectEmit(true, true, true, true);
        emit NameSet(name);
        token.setName(name);
        assertEq(token.name(), name);
    }

    function testSetSymbol(string calldata symbol) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        token.setSymbol(symbol);

        vm.expectEmit(true, true, true, true);
        emit SymbolSet(symbol);
        token.setSymbol(symbol);
        assertEq(token.symbol(), symbol);
    }

    function testSetRestrictor(address account) public {
        vm.assume(account != address(this));

        vm.expectEmit(true, true, true, true);
        emit TransferRestrictorSet(ITransferRestrictor(account));
        token.setTransferRestrictor(ITransferRestrictor(account));
        assertEq(address(token.transferRestrictor()), account);
    }

    function testMintFixed() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, 1e18);
        assertEq(token.totalSupply(), 1e18);
        assertEq(token.balanceOf(user), 1e18);
    }

    function testMintUnauthorizedReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.MINTER_ROLE())
        );
        vm.prank(user);
        token.mint(user, 1e18);
    }

    function testBurnFixed() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, 1e18);
        token.grantRole(token.BURNER_ROLE(), user);

        vm.prank(user);
        token.burn(0.9e18);
        assertEq(token.totalSupply(), 0.1e18);
        assertEq(token.balanceOf(user), 0.1e18);
    }

    function testBurnUnauthorizedReverts() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, 1e18);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.BURNER_ROLE())
        );
        vm.prank(user);
        token.burn(0.9e18);
    }

    function testTransferOwnerShip() public {
        // set new address
        address newAdmin = user;
        assertEq(token.hasRole(0, address(this)), true);
        vm.expectRevert(IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminRules.selector);
        token.revokeRole(0, address(this));

        // begin admin transfer
        token.beginDefaultAdminTransfer(newAdmin);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlInvalidDefaultAdmin.selector, address(this)
            )
        );
        token.acceptDefaultAdminTransfer();

        vm.startPrank(newAdmin);

        (, uint48 schedule) = token.pendingDefaultAdmin();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminDelay.selector, schedule
            )
        );
        token.acceptDefaultAdminTransfer();

        // warp block with 1 seconds
        vm.warp(block.timestamp + 1 seconds);

        // new owner accept admin transfer
        token.acceptDefaultAdminTransfer();

        vm.stopPrank();

        assertEq(token.hasRole(0, address(this)), false);
        assertEq(token.owner(), newAdmin);
    }

    function testSetBalancePerShareZeroReverts() public {
        vm.expectRevert(DShare.ZeroValue.selector);
        token.setBalancePerShare(0);
    }

    function testSetBalancePerShare(uint128 balancePerShare) public {
        vm.assume(balancePerShare > 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        token.setBalancePerShare(balancePerShare);

        vm.expectEmit(true, true, true, true);
        emit BalancePerShareSet(balancePerShare);
        token.setBalancePerShare(balancePerShare);
        assertEq(token.balancePerShare(), balancePerShare);
    }

    function _nearestBalanceAmount(uint256 amount) internal view returns (uint256) {
        return token.sharesToBalance(token.balanceToShares(amount));
    }

    function testMintUnauthorizedReverts(uint256 amount) public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.MINTER_ROLE())
        );
        vm.prank(user);
        token.mint(user, amount);
    }

    function testMint(uint256 amount, uint128 balancePerShare) public {
        vm.assume(balancePerShare > 0);
        vm.assume(!checkMintOverFlow(amount, balancePerShare));

        token.setBalancePerShare(balancePerShare);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, amount);
        uint256 balance = _nearestBalanceAmount(amount);
        assertLe(token.totalSupply(), balance);
        assertLe(token.balanceOf(user), balance);
    }

    function testBurnUnauthorizedReverts(uint256 amount) public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, amount);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.BURNER_ROLE())
        );
        vm.prank(user);
        token.burn(amount);
    }

    function testBurn(uint256 amount, uint128 balancePerShare) public {
        vm.assume(balancePerShare > 0);
        vm.assume(!checkMintOverFlow(amount, balancePerShare));

        token.setBalancePerShare(balancePerShare);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, amount);
        token.grantRole(token.BURNER_ROLE(), user);

        uint256 userBalance = token.balanceOf(user);
        vm.prank(user);
        token.burn(userBalance);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(user), 0);
    }

    function testBurnFrom(uint256 amount, uint128 balancePerShare) public {
        vm.assume(balancePerShare > 0);
        vm.assume(!checkMintOverFlow(amount, balancePerShare));

        token.setBalancePerShare(balancePerShare);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, amount);
        token.grantRole(token.BURNER_ROLE(), address(this));

        uint256 userBalance = token.balanceOf(user);
        vm.prank(user);
        token.approve(address(this), userBalance);

        token.burnFrom(user, userBalance);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(user), 0);
    }

    function testTransfer(uint256 amount, uint128 balancePerShare) public {
        vm.assume(balancePerShare > 0);
        vm.assume(!checkMintOverFlow(amount, balancePerShare));

        token.setBalancePerShare(balancePerShare);

        uint256 balance = _nearestBalanceAmount(amount);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(address(this), amount);

        uint256 senderBalance = token.balanceOf(address(this));
        assertTrue(token.transfer(user, senderBalance));
        assertLe(token.totalSupply(), balance);

        // Can collect dust
        // assertEq(token.balanceOf(address(this)), 0);
        assertLe(token.balanceOf(user), balance);
    }

    function testTransferRestrictedTo(uint256 amount) public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, amount);
        vm.prank(restrictor_role);
        restrictor.restrict(user);
        assertTrue(token.isBlacklisted(user));

        vm.expectRevert(TransferRestrictor.AccountRestricted.selector);
        token.transfer(user, amount);

        token.setTransferRestrictor(ITransferRestrictor(address(0)));
        assertFalse(token.isBlacklisted(user));
    }

    function testTransferRestrictedFrom(uint256 amount) public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, amount);
        vm.prank(restrictor_role);
        restrictor.restrict(user);
        assertTrue(token.isBlacklisted(user));

        vm.expectRevert(TransferRestrictor.AccountRestricted.selector);
        token.transfer(user, amount);

        token.setTransferRestrictor(ITransferRestrictor(address(0)));
        assertFalse(token.isBlacklisted(user));
    }

    function testRebase(uint256 amount, uint128 balancePerShare) public {
        vm.assume(balancePerShare > 0);
        vm.assume(!NumberUtils.mulDivCheckOverflow(amount, 1 ether, balancePerShare));
        vm.assume(!NumberUtils.mulDivCheckOverflow(amount, balancePerShare, 1 ether));

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, amount);

        token.setBalancePerShare(balancePerShare);

        uint256 balance = token.sharesToBalance(amount);
        assertEq(token.totalSupply(), balance);
        assertEq(token.balanceOf(user), balance);
    }

    function testMaxSupply(uint128 balancePerShare_) public {
        vm.assume(balancePerShare_ > 0); // From testSetBalancePerShareZeroReverts
        // Skip cases where multiplication would overflow
        vm.assume(!NumberUtils.mulDivCheckOverflow(type(uint256).max, balancePerShare_, 1 ether));

        // Set the balance per share
        token.setBalancePerShare(balancePerShare_);

        // Get actual max supply
        uint256 maxSupply = token.maxSupply();

        // Compare with expected value based on balancePerShare
        if (balancePerShare_ == 1 ether) {
            assertEq(maxSupply, type(uint256).max);
        } else if (balancePerShare_ < 1 ether) {
            assertEq(maxSupply, FixedPointMathLib.fullMulDiv(type(uint256).max, balancePerShare_, 1e18));
        } else {
            assertEq(maxSupply, FixedPointMathLib.fullMulDiv(type(uint256).max, 1 ether, balancePerShare_));
        }
    }
}
