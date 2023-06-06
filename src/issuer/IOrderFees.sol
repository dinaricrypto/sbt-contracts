// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @notice
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/IOrderFees.sol)
interface IOrderFees {
    function flatFeeForOrder(address token) external view returns (uint256);

    function percentageFeeOnRemainingValue(uint256 value) external view returns (uint256);

    function percentageFeeForValue(uint256 value) external view returns (uint256);

    function recoverInputValueFromFee(uint256 remainingValue) external view returns (uint256);

    function recoverInputValueFromFeeOnRemaining(uint256 remainingValue) external view returns (uint256);
}
