// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

interface IVault {
    function withdrawFunds(address token, address user, uint256 amount) external;
}
