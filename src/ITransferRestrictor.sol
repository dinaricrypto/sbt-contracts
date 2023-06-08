// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @notice
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/KycManager.sol)
/// @author Modified from OpenEden (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/KycManager.sol)
interface ITransferRestrictor {
    enum KycType {
        NONE,
        DOMESTIC,
        INTERNATIONAL
    }

    struct User {
        KycType kycType;
        bool isBanned;
    }

    /// @notice Checks if the transfer is allowed
    /// @param from The address of the sender
    /// @param to The address of the recipient
    function requireNotRestricted(address from, address to) external view;

    /// @notice Checks if the account is banned
    /// @param account The address of the account
    function isBanned(address account) external view returns (bool);

    /// @notice Checks if the account has KYC status
    /// @param account The address of the account
    function isKyc(address account) external view returns (bool);
}
