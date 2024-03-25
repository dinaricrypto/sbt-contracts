// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

// Methods of the form `function blacklist(address account) external returns (bool)`

interface IERC20Usdc {
    function isBlacklisted(address account) external view returns (bool);
}

interface IERC20Usdt {
    function isBlackListed(address account) external view returns (bool);
}
