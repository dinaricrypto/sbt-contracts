// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "./ITransferRestrictor.sol";

/// @notice Enforces transfer restrictions
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/TransferRestrictor.sol)
contract TransferRestrictor is Ownable2Step, ITransferRestrictor {
    error AccountRestricted();

    event Restricted(address indexed account);
    event Unrestricted(address indexed account);

    /// @notice If an account is listed, it cannot send or receive tokens
    mapping(address => bool) public blacklist;

    constructor(address owner) {
        _transferOwnership(owner);
    }

    /*//////////////////////////////////////////////////////////////
                    OPERATIONS CALLED BY OWNER
    //////////////////////////////////////////////////////////////*/

    function restrict(address account) external onlyOwner {
        blacklist[account] = true;
        emit Restricted(account);
    }

    function unrestrict(address account) external onlyOwner {
        blacklist[account] = false;
        emit Unrestricted(account);
    }

    /*//////////////////////////////////////////////////////////////
                            USED BY INTERFACE
    //////////////////////////////////////////////////////////////*/
    /// @inheritdoc ITransferRestrictor
    function requireNotRestricted(address from, address to) external view virtual {
        if (blacklist[from] || blacklist[to]) {
            revert AccountRestricted();
        }
    }
}
