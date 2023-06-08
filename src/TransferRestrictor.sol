// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "./ITransferRestrictor.sol";

// each address can have a single kyc location
// each location can have transfer rules
// deploy a transfer restrictor per location

/// @notice Enforces jurisdictional restrictions
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/KycManager.sol)
/// @author Modified from OpenEden (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/KycManager.sol)
contract TransferRestrictor is Ownable2Step, ITransferRestrictor {
    error AccountBanned();
    error AccountRestricted();

    event KycSet(address indexed account, KycType kycType);
    event KycReset(address indexed account);
    event Banned(address indexed account);
    event UnBanned(address indexed account);

    /// @dev User information
    mapping(address => User) private userList;

    constructor(address owner) {
        _transferOwnership(owner);
    }

    /*//////////////////////////////////////////////////////////////
                    OPERATIONS CALLED BY OWNER
    //////////////////////////////////////////////////////////////*/

    function setKyc(address account, KycType kycType) external onlyOwner {
        userList[account].kycType = kycType;
        emit KycSet(account, kycType);
    }

    function resetKyc(address account) external onlyOwner {
        delete userList[account].kycType;
        emit KycReset(account);
    }

    function ban(address account) external onlyOwner {
        User storage user = userList[account];
        user.isBanned = true;
        emit Banned(account);
    }

    function unBan(address account) external onlyOwner {
        User storage user = userList[account];
        user.isBanned = false;
        emit UnBanned(account);
    }

    /*//////////////////////////////////////////////////////////////
                            USED BY INTERFACE
    //////////////////////////////////////////////////////////////*/
    function getUserInfo(address account) external view returns (User memory user) {
        user = userList[account];
    }

    function requireNotRestricted(address from, address to) external view virtual {
        if (userList[from].isBanned) revert AccountBanned();
        if (userList[to].isBanned) revert AccountBanned();

        // Reg S - cannot transfer to domestic account
        if (userList[to].kycType == KycType.DOMESTIC) {
            revert AccountRestricted();
        }
    }

    function isBanned(address account) external view returns (bool) {
        return userList[account].isBanned;
    }

    function isKyc(address account) external view returns (bool) {
        return KycType.NONE != userList[account].kycType;
    }
}
