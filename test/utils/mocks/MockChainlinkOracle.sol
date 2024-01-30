// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract MockChainlinkOracle {
    uint80 private constant ROUNDID = 18446744073710058517;

    string public description;
    int256 private price;

    /// @dev e.g. (ETH/USD, 223980000000)
    constructor(string memory _description, int256 initialPrice) {
        description = _description;
        price = initialPrice;
    }

    function setPrice(int256 newPrice) external {
        price = newPrice;
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 _roundId)
        public
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, price, block.number, block.number, _roundId);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return getRoundData(ROUNDID);
    }
}
