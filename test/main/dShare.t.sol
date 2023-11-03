// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {dShare} from "../../src/dShare.sol";
import {TransferRestrictor, ITransferRestrictor} from "../../src/TransferRestrictor.sol";
import {
    IAccessControlDefaultAdminRules,
    IAccessControl
} from "openzeppelin-contracts/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

contract dShareTest is Test {
    event NameSet(string name);
    event SymbolSet(string symbol);
    event DisclosuresSet(string disclosures);
    event TransferRestrictorSet(ITransferRestrictor indexed transferRestrictor);

    TransferRestrictor public restrictor;
    dShare public token;

    address public constant restrictor_role = address(1);
    address public constant user = address(2);

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        token = new dShare(
            address(this),
            "Dinari Token",
            "dTKN",
            "example.com",
            restrictor
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

    function testSetDisclosures(string calldata disclosures) public {
        vm.expectEmit(true, true, true, true);
        emit DisclosuresSet(disclosures);
        token.setDisclosures(disclosures);
        assertEq(token.disclosures(), disclosures);
    }

    function testSetRestrictor(address account) public {
        vm.expectEmit(true, true, true, true);
        emit TransferRestrictorSet(ITransferRestrictor(account));
        token.setTransferRestrictor(ITransferRestrictor(account));
        assertEq(address(token.transferRestrictor()), account);
    }

    function testMint() public {
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

    function testBurn() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, 1e18);
        token.grantRole(token.BURNER_ROLE(), user);

        vm.prank(user);
        token.burn(0.9e18);
        assertEq(token.totalSupply(), 0.1e18);
        assertEq(token.balanceOf(user), 0.1e18);
    }

    function testBurnFrom() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, 1e18);
        token.grantRole(token.BURNER_ROLE(), address(this));

        vm.prank(user);
        token.approve(address(this), 0.9e18);

        token.burnFrom(user, 0.9e18);
        assertEq(token.totalSupply(), 0.1e18);
        assertEq(token.balanceOf(user), 0.1e18);
    }

    function testAttemptToFalsifyTotalsupply() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(user, 1e18);

        // invalid burn
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(user);
        token.transfer(address(0), 0.1e18);
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

        assertEq(token.hasRole(0, address(this)), false);
        assertEq(token.owner(), newAdmin);
    }

    function testTransfer() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(address(this), 1e18);

        assertTrue(token.transfer(user, 1e18));
        assertEq(token.totalSupply(), 1e18);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(user), 1e18);
    }

    function testTransferRestrictedTo() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(address(this), 1e18);
        vm.prank(restrictor_role);
        restrictor.restrict(user);

        vm.expectRevert(TransferRestrictor.AccountRestricted.selector);
        token.transfer(user, 1e18);

        // works if restrictor removed
        token.setTransferRestrictor(ITransferRestrictor(address(0)));
        token.transfer(user, 1e18);
    }

    function testTransferRestrictedFrom() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(address(this), 1e18);
        vm.prank(restrictor_role);
        restrictor.restrict(address(this));

        vm.expectRevert(TransferRestrictor.AccountRestricted.selector);
        token.transfer(user, 1e18);

        // works if restrictor removed
        token.setTransferRestrictor(ITransferRestrictor(address(0)));
        token.transfer(user, 1e18);
    }

    function testRebase(uint256 amount) public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(address(this), amount);

        uint256 balancePerShare = token.balancePerShare();
        if (amount > type(uint256).max / 2) {
            vm.expectRevert(Math.MathOverflowedMulDiv.selector);
            token.setBalancePerShare(uint128(balancePerShare * 2));
            return;
        }

        token.setBalancePerShare(uint128(balancePerShare * 2));
        assertEq(token.totalSupply(), amount * 2);
        assertEq(token.balanceOf(address(this)), amount * 2);

        // test transfer math
        // vm.prank(user);
        // token.transfer(address(this), amount);
        // assertEq(token.balanceOf(address(this)), amount);
    }
}
