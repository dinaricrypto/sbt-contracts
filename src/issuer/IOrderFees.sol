// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @notice
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/IOrderFees.sol)
interface IOrderFees {
    function flatFeeForOrder(address token) external view returns (uint256);

    function percentageFeeOnRemainingValue(uint256 value) external view returns (uint256);

    function percentageFeeForValue(uint256 value) external view returns (uint256);

    /// @notice Returns the fees for an order as if fees were added to order value.
    /// @param token The token to pay the fees in.
    /// @param inputValue The token value of the order.
    function feesForOrderUpfront(address token, uint256 inputValue)
        external
        view
        returns (uint256 flatFee, uint256 percentageFee);

    function inputValueForOrderValueUpfrontFees(address token, uint256 orderValue)
        external
        view
        returns (uint256 inputValue);
}
