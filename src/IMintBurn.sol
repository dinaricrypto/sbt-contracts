// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

/// @notice Interface for token minting and burning
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/IMintBurn.sol)
/// Implemented implicitly by BridgedERC20
interface IMintBurn {
    /// @notice Mint new tokens
    /// @param to Address to mint tokens to
    /// @param value Amount of tokens to mint
    function mint(address to, uint256 value) external;

    /// @notice Burn tokens
    /// @param value Amount of tokens to burn
    function burn(uint256 value) external;
}
