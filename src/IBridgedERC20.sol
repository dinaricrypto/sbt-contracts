// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/IDinariERC20.sol)
interface IBridgedERC20 {
    function mint(address to, uint256 value) external;

    function burn(uint256 value) external;
}
