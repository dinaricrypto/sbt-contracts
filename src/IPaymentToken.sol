// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

interface IPaymentToken {
    function isBlacklisted(address _account) external view returns (bool);
}
