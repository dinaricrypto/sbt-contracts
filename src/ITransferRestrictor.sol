// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

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

    function requireNotRestricted(address from, address to) external view;

    function isBanned(address account) external view returns (bool);

    function isKyc(address account) external view returns (bool);
}
