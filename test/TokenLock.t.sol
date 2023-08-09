// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";
import {TokenLockCheck} from "../src/TokenLockCheck.sol";

contract TokenLockTest is Test {
    MockToken token;
    MockToken token2;
    TokenLockCheck tokenLockCheck;
    address user;

    function setUp() public {
        user = address(1);
        token = new MockToken();
        token2 = new MockToken();
        tokenLockCheck = new TokenLockCheck(address(token), address(token2));
    }

    function testGetter() public {
        assertEq(tokenLockCheck.isTransferLocked(address(token), user), false);
        assertEq(tokenLockCheck.isTransferLocked(address(token2), user), false);
    }

    function testLocked() public {
        token.blacklist(user);
        token2.blackList(user);
        assertEq(tokenLockCheck.isTransferLocked(address(token), user), true);
        assertEq(tokenLockCheck.isTransferLocked(address(token2), user), true);
    }
}
