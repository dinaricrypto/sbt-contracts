// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

/// @notice Interface for contracts specifying fees for orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/issuer/IOrderFees.sol)
interface IOrderFees {
    /// @notice Calculates flat fee for an order
    /// @param token Token for order
    function flatFeeForOrder(address token) external view returns (uint256);

    /// @notice Calculates percentage fee for an order
    /// @param value Value of order subject to percentage fee
    function percentageFeeForValue(uint256 value) external view returns (uint256);

    /// @notice Recovers input value needed to achieve a given remaining value after fees
    /// @param remainingValue Remaining value after fees
    function recoverInputValueFromRemaining(uint256 remainingValue) external view returns (uint256);
}
