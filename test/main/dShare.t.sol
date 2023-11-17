// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../../src/dShare.sol";
import {TransferRestrictor, ITransferRestrictor} from "../../src/TransferRestrictor.sol";
import {
    IAccessControlDefaultAdminRules,
    IAccessControl
} from "openzeppelin-contracts/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {PRBMath_MulDiv18_Overflow, PRBMath_MulDiv_Overflow} from "prb-math/Common.sol";
import {NumberUtils} from "../utils/NumberUtils.sol";

contract dShareTest is Test {
    event NameSet(string name);
    event SymbolSet(string symbol);
    event TransferRestrictorSet(ITransferRestrictor indexed transferRestrictor);
    event BalancePerShareSet(uint256 balancePerShare);

    TransferRestrictor restrictor;
    dShare token;
    address restrictor_role = address(1);
    address user = address(2);

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        dShare tokenImplementation = new dShare();
        token = dShare(
            address(
                new ERC1967Proxy(
                address(tokenImplementation),
                abi.encodeCall(dShare.initialize, (address(this), "Dinari Token", "dTKN", restrictor))
                )
            )
        );
        restrictor.grantRole(restrictor.RESTRICTOR_ROLE(), restrictor_role);
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

        assertEq(token.hasRole(0, address(this)), false);
        assertEq(token.owner(), newAdmin);
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

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        token.setTransferRestrictor(ITransferRestrictor(account));

        vm.expectEmit(true, true, true, true);
        emit TransferRestrictorSet(ITransferRestrictor(account));
        token.setTransferRestrictor(ITransferRestrictor(account));
        assertEq(address(token.transferRestrictor()), account);
    }

    function testSetBalancePerShareZeroReverts() public {
        vm.expectRevert(stdError.divisionError);
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
        vm.assume(!NumberUtils.mulDivCheckOverflow(amount, 1 ether, balancePerShare));

        token.setBalancePerShare(balancePerShare);

        uint256 balance = _nearestBalanceAmount(amount);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, amount);
        assertEq(token.totalSupply(), balance);
        assertEq(token.balanceOf(user), balance);
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
        vm.assume(!NumberUtils.mulDivCheckOverflow(amount, 1 ether, balancePerShare));

        token.setBalancePerShare(balancePerShare);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, amount);
        token.grantRole(token.BURNER_ROLE(), user);

        vm.prank(user);
        token.burn(amount);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(user), 0);
    }

    function testBurnFrom(uint256 amount, uint128 balancePerShare) public {
        vm.assume(balancePerShare > 0);
        vm.assume(!NumberUtils.mulDivCheckOverflow(amount, 1 ether, balancePerShare));

        token.setBalancePerShare(balancePerShare);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, amount);
        token.grantRole(token.BURNER_ROLE(), address(this));

        vm.prank(user);
        token.approve(address(this), amount);

        token.burnFrom(user, amount);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(user), 0);
    }

    function testTransfer(uint256 amount, uint128 balancePerShare) public {
        vm.assume(balancePerShare > 0);
        vm.assume(!NumberUtils.mulDivCheckOverflow(amount, 1 ether, balancePerShare));

        token.setBalancePerShare(balancePerShare);

        uint256 balance = _nearestBalanceAmount(amount);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(address(this), amount);

        assertTrue(token.transfer(user, amount));
        assertEq(token.totalSupply(), balance);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(user), balance);
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

    function testRebase(uint256 amount) public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, amount);

        uint256 balancePerShare = token.balancePerShare();
        if (amount > type(uint256).max / 2) {
            vm.expectRevert(abi.encodeWithSelector(PRBMath_MulDiv18_Overflow.selector, amount, balancePerShare * 2));
            token.setBalancePerShare(uint128(balancePerShare * 2));
            return;
        }

        token.setBalancePerShare(uint128(balancePerShare * 2));
        assertEq(token.totalSupply(), amount * 2);
        assertEq(token.balanceOf(user), amount * 2);

        // test transfer math
        // vm.prank(user);
        // token.transfer(address(this), amount);
        // assertEq(token.balanceOf(address(this)), amount);
    }
}
