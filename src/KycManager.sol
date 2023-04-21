// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "solady/auth/Ownable.sol";
import "./IKycManager.sol";

/// @notice
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/KycManager.sol)
/// @author Modified from OpenEden (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/KycManager.sol)
contract KycManager is IKycManager, Ownable {
    event GrantKyc(address investor, KycType kycType);
    event RevokeKyc(address investor, KycType kycType);
    event Banned(address investor);
    event UnBanned(address investor);
    event SetStrict(bool status);

    mapping(address => User) userList;
    bool strictOn;

    /*//////////////////////////////////////////////////////////////
                    OPERATIONS CALLED BY OWNER
    //////////////////////////////////////////////////////////////*/

    function grantKyc(address investor, KycType kycType) external onlyOwner {
        require(
            KycType.US_KYC == kycType || KycType.GENERAL_KYC == kycType,
            "invalid kyc type"
        );

        User storage user = userList[investor];
        user.kycType = kycType;
        emit GrantKyc(investor, kycType);
    }

    function revokeKyc(address investor) external onlyOwner {
        User storage user = userList[investor];
        emit RevokeKyc(investor, user.kycType);

        user.kycType = KycType.NON_KYC;
    }

    function banned(address investor) external onlyOwner {
        User storage user = userList[investor];
        user.isBanned = true;
        emit Banned(investor);
    }

    function unBanned(address investor) external onlyOwner {
        User storage user = userList[investor];
        user.isBanned = false;
        emit UnBanned(investor);
    }

    function setStrict(bool status) external onlyOwner {
        strictOn = status;
        emit SetStrict(status);
    }

    /*//////////////////////////////////////////////////////////////
                            USED BY INTERFACE
    //////////////////////////////////////////////////////////////*/
    function getUserInfo(
        address investor
    ) external view returns (User memory user) {
        user = userList[investor];
    }

    function onlyNotBanned(address investor) external view {
        require(!userList[investor].isBanned, "user is banned");
    }

    function onlyKyc(address investor) external view {
        require(
            KycType.NON_KYC != userList[investor].kycType,
            "not a kyc user"
        );
    }

    function isBanned(address investor) external view returns (bool) {
        return userList[investor].isBanned;
    }

    function isKyc(address investor) external view returns (bool) {
        return KycType.NON_KYC != userList[investor].kycType;
    }

    function isUSKyc(address investor) external view returns (bool) {
        return KycType.US_KYC == userList[investor].kycType;
    }

    function isNonUSKyc(address investor) external view returns (bool) {
        return KycType.GENERAL_KYC == userList[investor].kycType;
    }

    function isStrict() external view returns (bool) {
        return strictOn;
    }
}
