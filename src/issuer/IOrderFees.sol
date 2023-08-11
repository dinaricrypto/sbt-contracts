// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

/// @notice Interface for contracts specifying fees for orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/issuer/IOrderFees.sol)
interface IOrderFees {
    /// @notice Return the current percentage fee rate
    function percentageFeeRate() external view returns (uint24);

    /// @notice Return the current perOrder fee
    function perOrderFee() external view returns (uint64);
}
