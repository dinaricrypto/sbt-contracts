// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "solady/auth/Ownable.sol";
import "./ITransferRestrictor.sol";

// each address can have a single kyc location
// each location can have transfer rules
// deploy a transfer restrictor per location

/// @notice Enforces jurisdictional restrictions
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/KycManager.sol)
/// @author Modified from OpenEden (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/KycManager.sol)
contract TransferRestrictor is ITransferRestrictor, Ownable {
    error AccountBanned(address account);
    error AccountRestricted(address account);

    event GrantKyc(address account, KycType kycType);
    event RevokeKyc(address account, KycType kycType);
    event Banned(address account);
    event UnBanned(address account);

    mapping(address => User) userList;

    /*//////////////////////////////////////////////////////////////
                    OPERATIONS CALLED BY OWNER
    //////////////////////////////////////////////////////////////*/

    function grantKyc(address account, KycType kycType) external onlyOwner {
        User storage user = userList[account];
        user.kycType = kycType;
        emit GrantKyc(account, kycType);
    }

    function revokeKyc(address account) external onlyOwner {
        User storage user = userList[account];
        emit RevokeKyc(account, user.kycType);

        delete user.kycType;
    }

    function banned(address account) external onlyOwner {
        User storage user = userList[account];
        user.isBanned = true;
        emit Banned(account);
    }

    function unBanned(address account) external onlyOwner {
        User storage user = userList[account];
        user.isBanned = false;
        emit UnBanned(account);
    }

    /*//////////////////////////////////////////////////////////////
                            USED BY INTERFACE
    //////////////////////////////////////////////////////////////*/
    function getUserInfo(
        address account
    ) external view returns (User memory user) {
        user = userList[account];
    }

    function requireNotRestricted(
        address from,
        address to
    ) external view virtual {
        if (userList[from].isBanned) revert AccountBanned(from);
        if (userList[to].isBanned) revert AccountBanned(to);

        // Reg S - cannot transfer to domestic account
        if (userList[to].kycType == KycType.DOMESTIC)
            revert AccountRestricted(to);
    }

    function isBanned(address account) external view returns (bool) {
        return userList[account].isBanned;
    }

    function isKyc(address account) external view returns (bool) {
        return KycType.NONE != userList[account].kycType;
    }

    function isDomesticKyc(address account) external view returns (bool) {
        return KycType.DOMESTIC == userList[account].kycType;
    }

    function isInternationalKyc(address account) external view returns (bool) {
        return KycType.INTERNATIONAL == userList[account].kycType;
    }
}
