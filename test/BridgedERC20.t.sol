// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {BridgedERC20} from "../src/BridgedERC20.sol";
import {TransferRestrictor, ITransferRestrictor} from "../src/TransferRestrictor.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

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
                    Strings.toHexString(address(this)),
                    " is missing role ",
                    Strings.toHexString(uint256(token.MINTER_ROLE()), 32)
                )
            )
        );
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
        restrictor.restrict(address(1));

        vm.expectRevert(TransferRestrictor.AccountRestricted.selector);
        token.transfer(address(1), 1e18);
    }

    function testTransferRestrictedFromReverts() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(address(this), 1e18);
        restrictor.restrict(address(this));

        vm.expectRevert(TransferRestrictor.AccountRestricted.selector);
        token.transfer(address(1), 1e18);
    }
}
