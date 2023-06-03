// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @notice
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/IOrderFees.sol)
interface IOrderFees {
    function flatFeeForOrder(address token) external view returns (uint256 flatFee);

    /// @notice Returns the fees for an order.
    /// @param token The token to pay the fees in.
    /// @param value The token value of the order.
    function feesForOrderUpfront(address token, uint256 value)
        external
        view
        returns (uint256 flatFee, uint256 percentageFee);

    function feesOnProceeds(address token, uint256 value)
        external
        view
        returns (uint256 flatFee, uint256 percentageFee);
}
