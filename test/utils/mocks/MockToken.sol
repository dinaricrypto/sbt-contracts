// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "solady/test/utils/mocks/MockERC20.sol";

contract MockToken is MockERC20 {
    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public isBlackListed;
    mapping(address => bool) public isBlocked;

    constructor(string memory name_, string memory symbol_) MockERC20(name_, symbol_, 6) {}

    function blacklist(address account) public {
        isBlacklisted[account] = true;
        isBlackListed[account] = true;
        isBlocked[account] = true;
    }
}
