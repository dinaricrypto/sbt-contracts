// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {dShare} from "../../src/dShare.sol";
import {TransferRestrictor, ITransferRestrictor} from "../../src/TransferRestrictor.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract dShareTest is Test {
    event NameSet(string name);
    event SymbolSet(string symbol);
    event DisclosuresSet(string disclosures);
    event TransferRestrictorSet(ITransferRestrictor indexed transferRestrictor);

    TransferRestrictor public restrictor;
    dShare public token;
    address public restrictor_role = address(1);

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
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(address(1)),
                    " is missing role ",
                    Strings.toHexString(uint256(token.DEFAULT_ADMIN_ROLE()), 32)
                )
            )
        );
        vm.prank(address(1));
        token.setName(name);

        vm.expectEmit(true, true, true, true);
        emit NameSet(name);
        token.setName(name);
        assertEq(token.name(), name);
    }

    function testSetSymbol(string calldata symbol) public {
        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(address(1)),
                    " is missing role ",
                    Strings.toHexString(uint256(token.DEFAULT_ADMIN_ROLE()), 32)
                )
            )
        );
        vm.prank(address(1));
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

    function testSetSplitReverts() public {
        vm.expectRevert(dShare.Unauthorized.selector);
        vm.prank(address(1));
        token.setSplit();
    }

    function testMint() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(address(1), 1e18);
        assertEq(token.totalSupply(), 1e18);
        assertEq(token.balanceOf(address(1)), 1e18);
    }

    function testMintUnauthorizedReverts() public {
        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(address(1)),
                    " is missing role ",
                    Strings.toHexString(uint256(token.MINTER_ROLE()), 32)
                )
            )
        );
        vm.prank(address(1));
        token.mint(address(1), 1e18);
    }

    function testBurn() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(address(1), 1e18);
        token.grantRole(token.BURNER_ROLE(), address(1));

        vm.prank(address(1));
        token.burn(0.9e18);
        assertEq(token.totalSupply(), 0.1e18);
        assertEq(token.balanceOf(address(1)), 0.1e18);
    }

    function testAttemptToFalsifyTotalsupply() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.BURNER_ROLE(), address(2));
        token.mint(address(1), 1e18);
        token.mint(address(2), 1e18);
        vm.expectRevert(dShare.Unauthorized.selector);
        vm.prank(address(1));
        token.transfer(address(0), 0.1e18);

        vm.prank(address(2));
        token.burn(0.9e18);
    }

    function testBurnUnauthorizedReverts() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(address(1), 1e18);

        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(address(1)),
                    " is missing role ",
                    Strings.toHexString(uint256(token.BURNER_ROLE()), 32)
                )
            )
        );
        vm.prank(address(1));
        token.burn(0.9e18);
    }

    function testTransferOwnerShip() public {
        // set new address
        address newAdmin = address(1);
        assertEq(token.hasRole(0, address(this)), true);
        vm.expectRevert("AccessControl: can't directly revoke default admin role");
        token.revokeRole(0, address(this));

        // begin admin transfer
        token.beginDefaultAdminTransfer(newAdmin);

        vm.expectRevert("AccessControl: pending admin must accept");
        token.acceptDefaultAdminTransfer();

        vm.startPrank(newAdmin);

        vm.expectRevert("AccessControl: transfer delay not passed");
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

        assertTrue(token.transfer(address(1), 1e18));
        assertEq(token.totalSupply(), 1e18);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(1)), 1e18);
    }

    function testTransferRestrictedToReverts() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(address(this), 1e18);
        vm.prank(restrictor_role);
        restrictor.restrict(address(1));

        vm.expectRevert(TransferRestrictor.AccountRestricted.selector);
        token.transfer(address(1), 1e18);
    }

    function testTransferRestrictedFromReverts() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(address(this), 1e18);
        vm.prank(restrictor_role);
        restrictor.restrict(address(this));

        vm.expectRevert(TransferRestrictor.AccountRestricted.selector);
        token.transfer(address(1), 1e18);
    }
}