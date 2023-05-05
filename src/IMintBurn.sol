// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @notice
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/IMintBurn.sol)
interface IMintBurn {
    function mint(address to, uint256 value) external;

    function burn(uint256 value) external;
}
