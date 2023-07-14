// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "solady/test/utils/mocks/MockERC20.sol";

contract MockPaymentToken is MockERC20 {
    mapping(address => bool) public blacklisted;

    constructor() MockERC20("Money", "$", 6) {}

    function blacklist(address _account) external {
        blacklisted[_account] = true;
    }

    function isBlacklisted(address _account) external view returns (bool) {
        return blacklisted[_account];
    }
}
