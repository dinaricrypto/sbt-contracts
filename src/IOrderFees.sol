// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @notice
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/IOrderFees.sol)
interface IOrderFees {
    /// @notice Returns the fees for an order.
    /// @param token The token to pay the fees in.
    /// @param maker Whether the order is a maker order.
    /// @param value The token value of the order.
    function feesForOrder(address token, bool maker, uint256 value) external view returns (uint256);
}
