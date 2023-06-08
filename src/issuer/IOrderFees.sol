// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @notice
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/IOrderFees.sol)
interface IOrderFees {
    /// @notice Calculates flat fee for an order
    /// @param token Token for order
    function flatFeeForOrder(address token) external view returns (uint256);

    /// @notice Calculates percentage fee for an order
    /// @param value Value of order subject to percentage fee
    function percentageFeeForValue(uint256 value) external view returns (uint256);

    /// @notice Calculates percentage fee for an order as if fee was added to order value
    /// @param value Value of order subject to percentage fee
    function percentageFeeOnRemainingValue(uint256 value) external view returns (uint256);

    /// @notice Recovers input value needed to achieve a given remaining value after fees
    /// @param remainingValue Remaining value after fees
    function recoverInputValueFromFee(uint256 remainingValue) external view returns (uint256);

    /// @notice Recovers input value needed to achieve a given remaining value as if fee was added to order value
    /// @param remainingValue Remaining value after fees
    function recoverInputValueFromFeeOnRemaining(uint256 remainingValue) external view returns (uint256);
}
