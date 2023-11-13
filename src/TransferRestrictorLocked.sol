// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {ITransferRestrictor} from "./ITransferRestrictor.sol";

/// @notice Locks all transfers
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/TransferRestrictorLocked.sol)
contract TransferRestrictorLocked is ITransferRestrictor {
    /// @inheritdoc ITransferRestrictor
    function isBlacklisted(address) external pure returns (bool) {
        return true;
    }

    /// @inheritdoc ITransferRestrictor
    function requireNotRestricted(address, address) external view virtual {
        // Always revert
        revert AccountRestricted();
    }
}
