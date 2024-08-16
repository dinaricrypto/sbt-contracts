// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

///@notice Factory interface to create new dShares
///@author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/IDShareFactory.sol)
interface IDShareFactory {
    event DShareAdded(address indexed dShare, address indexed wrappedDShare, string indexed symbol, string name);

    function isTokenDShare(address token) external view returns (bool);

    function isTokenWrappedDShare(address token) external view returns (bool);

    /// @notice Gets list of all dShares and wrapped dShares
    /// @return dShares List of all dShares
    /// @return wrappedDShares List of all wrapped dShares
    /// @dev This function can be expensive
    function getDShares() external view returns (address[] memory, address[] memory);
}
