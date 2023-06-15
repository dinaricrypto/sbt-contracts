// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @notice Interface for transfer restriction contract
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/ITransferRestrictor.sol)
interface ITransferRestrictor {
    /// @notice Checks if the transfer is allowed
    /// @param from The address of the sender
    /// @param to The address of the recipient
    function requireNotRestricted(address from, address to) external view;
}
