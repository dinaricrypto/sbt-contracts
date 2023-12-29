// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

interface IDShareFactory {
    /// @notice Emitted when a new dShare is created
    event DShareCreated(address indexed dShare);

    /// @notice Creates a new dShare
    /// @param owner of the proxy
    /// @param name Name of the dShare
    /// @param symbol Symbol of the dShare
    /// @return Address of the new dShare
    function createDShare(address owner, string memory name, string memory symbol) external returns (address);
}
