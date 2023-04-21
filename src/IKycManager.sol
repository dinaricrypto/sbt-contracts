// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice 
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/KycManager.sol)
/// @author Modified from OpenEden (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/KycManager.sol)
interface IKycManager {
    enum KycType {
        NON_KYC,
        US_KYC,
        GENERAL_KYC
    }

    struct User {
        KycType kycType;
        bool isBanned;
    }

    function onlyNotBanned(address investor) external view;

    function onlyKyc(address investor) external view;

    function isBanned(address investor) external view returns (bool);

    function isKyc(address investor) external view returns (bool);

    function isUSKyc(address investor) external view returns (bool);

    function isNonUSKyc(address investor) external view returns (bool);

    function isStrict() external view returns (bool);
}
