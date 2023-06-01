// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {BridgedERC20} from "../src/BridgedERC20.sol";
import {TransferRestrictor, ITransferRestrictor} from "../src/TransferRestrictor.sol";

contract BridgedERC20Test is Test {
    event NameSet(string name);
    event SymbolSet(string symbol);
    event DisclosuresSet(string disclosures);
    event TransferRestrictorSet(ITransferRestrictor indexed transferRestrictor);

    TransferRestrictor public restrictor;
    BridgedERC20 public token;

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        token = new BridgedERC20(
            address(this),
            "Dinari Token",
            "dTKN",
            "example.com",
            restrictor
        );
    }

    function testSetName(string calldata name) public {
        vm.expectEmit(true, true, true, true);
        emit NameSet(name);
        token.setName(name);
        assertEq(token.name(), name);
    }

    function testSetSymbol(string calldata symbol) public {
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
        token.setMinter(address(this), true);
        token.mint(address(1), 1e18);
        assertEq(token.totalSupply(), 1e18);
        assertEq(token.balanceOf(address(1)), 1e18);
    }

    function testMintUnauthorizedReverts() public {
        vm.expectRevert(BridgedERC20.Unauthorized.selector);
        token.mint(address(1), 1e18);
    }

    function testBurn() public {
        token.setMinter(address(this), true);
        token.mint(address(1), 1e18);
        token.setMinter(address(1), true);

        vm.prank(address(1));
        token.burn(0.9e18);
        assertEq(token.totalSupply(), 0.1e18);
        assertEq(token.balanceOf(address(1)), 0.1e18);
    }

    function testBurnUnauthorizedReverts() public {
        token.setMinter(address(this), true);
        token.mint(address(1), 1e18);

        vm.expectRevert(BridgedERC20.Unauthorized.selector);
        vm.prank(address(1));
        token.burn(0.9e18);
    }

    function testTransfer() public {
        token.setMinter(address(this), true);
        token.mint(address(this), 1e18);

        assertTrue(token.transfer(address(1), 1e18));
        assertEq(token.totalSupply(), 1e18);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(1)), 1e18);
    }

    function testTransferBannedToReverts() public {
        token.setMinter(address(this), true);
        token.mint(address(this), 1e18);
        restrictor.ban(address(1));

        vm.expectRevert(TransferRestrictor.AccountBanned.selector);
        token.transfer(address(1), 1e18);
    }

    function testTransferBannedFromReverts() public {
        token.setMinter(address(this), true);
        token.mint(address(this), 1e18);
        restrictor.ban(address(this));

        vm.expectRevert(TransferRestrictor.AccountBanned.selector);
        token.transfer(address(1), 1e18);
    }

    function testTransferRestrictedToReverts() public {
        token.setMinter(address(this), true);
        token.mint(address(this), 1e18);
        restrictor.setKyc(address(1), ITransferRestrictor.KycType.DOMESTIC);

        vm.expectRevert(TransferRestrictor.AccountRestricted.selector);
        token.transfer(address(1), 1e18);
    }
}
