// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "solady/test/utils/mocks/MockERC20.sol";

contract MockToken is MockERC20 {
    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public isBlackListed;

    constructor() MockERC20("Money", "$", 6) {}

    function blacklist(address account) public {
        isBlacklisted[account] = true;
    }

    function blackList(address account) public {
        isBlackListed[account] = true;
    }
}
