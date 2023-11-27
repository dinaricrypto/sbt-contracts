// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

/**
 * @title IxdShare Interface
 * @dev Interface for the extended functionalities of the dShare token provided by the xdShare contract.
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/IxdShare.sol)
 */
interface IxdShare {
    /**
     * @param account The address of the account
     * @return Whether the account is blacklisted
     * @dev Returns true if the account is blacklisted , if the account is the zero address
     */
    function isBlacklisted(address account) external view returns (bool);
}
