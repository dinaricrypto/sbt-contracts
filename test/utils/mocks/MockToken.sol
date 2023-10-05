// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "solady/test/utils/mocks/MockERC20.sol";

contract MockToken is MockERC20 {
    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public isBlackListed;
    mapping(address => bool) public isBlocked;

    constructor(string memory mockTokenName, string memory mockTokenSymbol)
        MockERC20(mockTokenName, mockTokenSymbol, 6)
    {}

    function blacklist(address account) public {
        isBlacklisted[account] = true;
    }

    function blocked(address account) public {
        isBlocked[account] = true;
    }

    function blackList(address account) public {
        isBlackListed[account] = true;
    }
}
