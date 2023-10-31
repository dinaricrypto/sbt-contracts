// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "prb-math/Common.sol" as PrbMath;
import "../../src/dShareManager.sol";
import {TransferRestrictor} from "../../src/TransferRestrictor.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract dShareManagerTest is Test {
    using Strings for uint256;

    event TransferRestrictorSet(ITransferRestrictor transferRestrictor);
    event DisclosuresSet(string disclosures);
    event NewToken(dShare indexed token);
    event Split(
        dShare indexed legacyToken, dShare indexed newToken, uint8 multiple, bool reverseSplit, uint256 aggregateSupply
    );

    dShareManager tokenManager;
    TransferRestrictor restrictor;

    dShare token1;

    address user = address(2);

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        tokenManager = new dShareManager(restrictor);

        token1 = tokenManager.deployNewToken(address(this), "Dinari Token1", "TKN1.d");
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
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));
        vm.prank(address(1));
        tokenManager.setTransferRestrictor(ITransferRestrictor(address(1)));

        vm.expectEmit(true, true, true, true);
        emit TransferRestrictorSet(ITransferRestrictor(address(1)));
        tokenManager.setTransferRestrictor(ITransferRestrictor(address(1)));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));
        vm.prank(address(1));
        tokenManager.setDisclosures("example.com");

        vm.expectEmit(true, true, true, true);
        emit DisclosuresSet("example.com");
        tokenManager.setDisclosures("example.com");
    }

    function testDeployNewToken() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));
        vm.prank(address(1));
        tokenManager.deployNewToken(address(1), "Dinari Token", "TKN.d");

        dShare newToken = tokenManager.deployNewToken(address(1), "Dinari Token", "TKN.d");
        assertEq(newToken.owner(), address(1));
        assertEq(newToken.name(), "Dinari Token");
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
        string memory timestamp = block.timestamp.toString();
        if (multiple < 2) {
            vm.expectRevert(dShareManager.InvalidMultiple.selector);
            tokenManager.split(token1, multiple, reverse, timestamp, timestamp);
        } else if (!reverse && overflowChecker(supply, multiple)) {
            vm.expectRevert(stdError.arithmeticError);
            tokenManager.split(token1, multiple, reverse, timestamp, timestamp);
        } else {
            uint256 splitAmount = tokenManager.splitAmount(multiple, reverse, supply);
            vm.expectEmit(true, false, true, true);
            emit Split(token1, dShare(address(0)), multiple, reverse, splitAmount);
            (dShare newToken, uint256 aggregateSupply) =
                tokenManager.split(token1, multiple, reverse, timestamp, timestamp);
            assertEq(aggregateSupply, splitAmount);
            assertEq(newToken.owner(), token1.owner());
            assertEq(newToken.name(), string.concat("Dinari Token1"));
            assertEq(newToken.symbol(), string.concat("TKN1.d"));
            assertEq(newToken.disclosures(), "");
            assertEq(address(newToken.transferRestrictor()), address(restrictor));
            assertEq(token1.name(), string.concat("Dinari Token1", timestamp));
            assertEq(token1.symbol(), string.concat("TKN1.d", timestamp));
            assertEq(tokenManager.getNumTokens(), 1);
            assertEq(address(tokenManager.getTokenAt(0)), address(newToken));
            assertTrue(tokenManager.isCurrentToken(address(newToken)));
            assertFalse(tokenManager.isCurrentToken(address(token1)));
            assertEq(address(tokenManager.getCurrentToken(token1)), address(newToken));

            // split restrictions
            vm.expectRevert(dShare.TokenSplit.selector);
            token1.mint(user, 1);

            vm.expectRevert(dShare.TokenSplit.selector);
            vm.prank(user);
            token1.burn(1);

            dShare rootToken = tokenManager.getRootParent(newToken);
            assertEq(address(rootToken), address(token1));
        }
    }

    function testSplitReverts() public {
        string memory timestamp = block.timestamp.toString();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));
        vm.prank(address(1));
        tokenManager.split(token1, 2, false, timestamp, timestamp);

        vm.expectRevert(dShareManager.TokenNotFound.selector);
        tokenManager.split(dShare(address(1)), 2, false, timestamp, timestamp);
    }

    function testConvertTripleSplit(uint8 multiple, bool reverse, uint256 amount) public {
        vm.assume(multiple > 1);
        vm.assume(reverse || !overflowChecker(amount, uint256(multiple) * uint256(multiple) * multiple));

        // mint amount to user
        token1.mint(user, amount);
        // user approves token manager
        vm.prank(user);
        token1.approve(address(tokenManager), amount);

        string memory timestamp = block.timestamp.toString();
        // split token
        (dShare newToken,) = tokenManager.split(token1, multiple, reverse, timestamp, timestamp);
        // split token again
        (dShare newToken2,) = tokenManager.split(newToken, multiple, reverse, timestamp, timestamp);
        // split token again
        (dShare newToken3, uint256 aggregateSupply3) =
            tokenManager.split(newToken2, multiple, reverse, timestamp, timestamp);

        // convert amount
        vm.prank(user);
        (dShare currentToken, uint256 convertedAmount) = tokenManager.convert(token1, amount);
        assertEq(address(currentToken), address(newToken3));
        assertEq(aggregateSupply3, convertedAmount);
        if (reverse) {
            assertEq(convertedAmount, ((amount / multiple) / multiple) / multiple);
        } else {
            assertEq(convertedAmount, amount * multiple * multiple * multiple);
        }
        assertEq(token1.balanceOf(user), 0);
        assertEq(newToken.balanceOf(user), 0);
        assertEq(newToken2.balanceOf(user), 0);
        assertEq(newToken3.balanceOf(user), convertedAmount);
    }

    function testConvertSplitNotFoundReverts() public {
        vm.expectRevert(dShareManager.SplitNotFound.selector);
        tokenManager.convert(dShare(address(1)), 1);
    }

    function testGetAggregateSupply(uint256 amount, uint8 multiple, uint256 convertAmount) public {
        vm.assume(multiple > 1);
        vm.assume(!overflowChecker(amount, uint256(multiple) * uint256(multiple) * multiple));
        vm.assume(amount > convertAmount);
        token1.mint(user, amount);
        uint256 totalSupply = token1.totalSupply();
        string memory timestamp = block.timestamp.toString();
        (dShare newToken,) = tokenManager.split(token1, multiple, false, timestamp, timestamp);
        if (amount > 0) {
            vm.startPrank(user);
            token1.approve(address(tokenManager), convertAmount);
            tokenManager.convert(token1, convertAmount);
            vm.stopPrank();
            assertEq(tokenManager.getAggregateSupply(token1) + convertAmount, totalSupply);
            assertEq(tokenManager.getAggregateBalanceOf(token1, user) + convertAmount, totalSupply);
            assertEq((totalSupply - convertAmount) * multiple, tokenManager.getSupplyExpansion(token1, multiple, false));
        }
        // check if aggregateBalance of user > 0
        (dShare newToken2,) = tokenManager.split(newToken, multiple, true, timestamp, timestamp);
        (dShare newToken3,) = tokenManager.split(newToken2, multiple, false, timestamp, timestamp);
        assertGt(tokenManager.getAggregateBalanceOf(newToken3, user), 0);
    }
}
