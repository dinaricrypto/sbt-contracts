// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {UnityOracle} from "../../src/oracles/UnityOracle.sol";

contract UnityOracleTest is Test {
    UnityOracle private oracle;

    function setUp() public {
        oracle = new UnityOracle();
    }

    function testAll() public {
        assertEq(oracle.decimals(), 8);
        assertEq(oracle.description(), "One");
        assertEq(oracle.version(), 1);
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.getRoundData(0);
        assertEq(roundId, 0);
        assertEq(answer, 1e8);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
        (roundId, answer, startedAt, updatedAt, answeredInRound) = oracle.latestRoundData();
        assertEq(roundId, 0);
        assertEq(answer, 1e8);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
    }
}
