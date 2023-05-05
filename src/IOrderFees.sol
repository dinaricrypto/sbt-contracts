// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @notice
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/IOrderFees.sol)
interface IOrderFees {
    function getFees(bool sell, uint256 value) external view returns (uint256);
}
