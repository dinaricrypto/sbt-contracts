// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "prb-math/Common.sol" as PrbMath;
import "../src/TokenManager.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";

contract TokenManagerTest is Test {
    event NameSuffixSet(string nameSuffix);
    event SymbolSuffixSet(string symbolSuffix);
    event TransferRestrictorSet(ITransferRestrictor transferRestrictor);
    event DisclosuresSet(string disclosures);
    event NewToken(BridgedERC20 indexed token);
    event Split(BridgedERC20 indexed legacyToken, BridgedERC20 indexed newToken, uint8 multiple, bool reverseSplit);

    TokenManager tokenManager;
    TransferRestrictor restrictor;

    BridgedERC20 token1;

    address user = address(2);

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        tokenManager = new TokenManager(restrictor);

        // token1 = new BridgedERC20(address(this), "Token1", "TKN1", "example.com", restrictor);
        token1 = tokenManager.deployNewToken(address(this), "Token1", "TKN1");
        token1.grantRole(token1.MINTER_ROLE(), address(this));
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

    function testAdministration() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1));
        tokenManager.setNameSuffix(" - Dinero");

        vm.expectEmit(true, true, true, true);
        emit NameSuffixSet(" - Dinero");
        tokenManager.setNameSuffix(" - Dinero");

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1));
        tokenManager.setSymbolSuffix(".x");

        vm.expectEmit(true, true, true, true);
        emit SymbolSuffixSet(".x");
        tokenManager.setSymbolSuffix(".x");

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1));
        tokenManager.setTransferRestrictor(ITransferRestrictor(address(1)));

        vm.expectEmit(true, true, true, true);
        emit TransferRestrictorSet(ITransferRestrictor(address(1)));
        tokenManager.setTransferRestrictor(ITransferRestrictor(address(1)));

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1));
        tokenManager.setDisclosures("example.com");

        vm.expectEmit(true, true, true, true);
        emit DisclosuresSet("example.com");
        tokenManager.setDisclosures("example.com");
    }

    function testDeployNewToken() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1));
        tokenManager.deployNewToken(address(1), "Token", "TKN");

        BridgedERC20 newToken = tokenManager.deployNewToken(address(1), "Token", "TKN");
        assertEq(newToken.owner(), address(1));
        assertEq(newToken.name(), "Token - Dinari");
        assertEq(newToken.symbol(), "TKN.d");
        assertEq(newToken.disclosures(), "");
        assertEq(address(newToken.transferRestrictor()), address(restrictor));
        assertEq(tokenManager.getNumTokens(), 2);
        assertEq(address(tokenManager.getTokenAt(1)), address(newToken));
        assertTrue(tokenManager.isCurrentToken(address(newToken)));

        address[] memory tokens = tokenManager.getTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(token1));
        assertEq(tokens[1], address(newToken));
    }

    function testSplit(uint256 supply, uint8 multiple, bool reverse) public {
        // mint supply to user
        token1.mint(user, supply);

        if (multiple < 2) {
            vm.expectRevert(TokenManager.InvalidMultiple.selector);
            tokenManager.split(token1, multiple, reverse);
        } else if (!reverse && overflowChecker(supply, multiple)) {
            vm.expectRevert(stdError.arithmeticError);
            tokenManager.split(token1, multiple, reverse);
        } else {
            vm.expectEmit(true, false, true, true);
            emit Split(token1, BridgedERC20(address(0)), multiple, reverse);
            BridgedERC20 newToken = tokenManager.split(token1, multiple, reverse);
            assertEq(newToken.owner(), token1.owner());
            assertEq(newToken.name(), "Token1 - Dinari");
            assertEq(newToken.symbol(), "TKN1.d");
            assertEq(newToken.disclosures(), "");
            assertEq(address(newToken.transferRestrictor()), address(restrictor));
            assertEq(token1.name(), "Token1 - Dinari - pre1");
            assertEq(token1.symbol(), "TKN1.d.p1");
            assertEq(tokenManager.getNumTokens(), 1);
            assertEq(address(tokenManager.getTokenAt(0)), address(newToken));
            assertTrue(tokenManager.isCurrentToken(address(newToken)));
            assertFalse(tokenManager.isCurrentToken(address(token1)));

            // split restrictions
            vm.expectRevert(BridgedERC20.TokenSplit.selector);
            token1.mint(user, 1);

            vm.expectRevert(BridgedERC20.TokenSplit.selector);
            vm.prank(user);
            token1.burn(1);
        }
    }

    function testSplitReverts() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1));
        tokenManager.split(token1, 2, false);

        vm.expectRevert(TokenManager.TokenNotFound.selector);
        tokenManager.split(BridgedERC20(address(1)), 2, false);
    }

    function testConvert(uint8 multiple, bool reverse, uint256 amount) public {
        vm.assume(multiple > 1);
        vm.assume(reverse || !overflowChecker(amount, uint256(multiple) * multiple));

        // mint amount to user
        token1.mint(user, amount);
        // user approves token manager
        vm.prank(user);
        token1.approve(address(tokenManager), amount);

        // split token
        BridgedERC20 newToken = tokenManager.split(token1, multiple, reverse);
        // split token again
        BridgedERC20 newToken2 = tokenManager.split(newToken, multiple, reverse);

        // convert amount
        vm.prank(user);
        (BridgedERC20 currentToken, uint256 convertedAmount) = tokenManager.convert(token1, amount);
        assertEq(address(currentToken), address(newToken2));
        if (reverse) {
            assertEq(convertedAmount, (amount / multiple) / multiple);
        } else {
            assertEq(convertedAmount, amount * multiple * multiple);
        }
        assertEq(token1.balanceOf(user), 0);
        assertEq(newToken2.balanceOf(user), convertedAmount);
    }

    function testConvertSplitNotFoundReverts() public {
        vm.expectRevert(TokenManager.SplitNotFound.selector);
        tokenManager.convert(BridgedERC20(address(1)), 1);
    }
}
