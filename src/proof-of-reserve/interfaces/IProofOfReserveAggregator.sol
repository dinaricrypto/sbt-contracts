// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.19;

/**
 * @title IProofOfReserveAggregator
 * @dev This interface represents the functions of the ProofOfReserveAggregator contract.
 */
interface IProofOfReserveAggregator {
    event ProofOfReserveFeedStateChanged(address indexed asset, address indexed proofOfReserveFeed, bool enabled);
    /**
     * @dev Gets the Chainlink oracle feed for an asset
     * @param asset The address of the asset
     * @return The address of the Chainlink oracle feed for the asset
     */

    function getProofOfReserveFeedForAsset(address asset) external view returns (address);

    /**
     * @dev Enables a Chainlink oracle feed for an asset
     * @param asset The address of the asset
     * @param feed The address of the Chainlink oracle feed
     */
    function enableProofOfReserveFeed(address asset, address feed) external;

    /**
     * @dev Disables the Chainlink oracle feed for an asset
     * @param asset The address of the asset
     */
    function disableProofOfReserveFeed(address asset) external;

    /**
     * @dev Checks whether the reserves for a list of assets are fully backed
     * @param asset The list of asset addresses
     * @return A boolean indicating whether all reserves are fully backed and an array of booleans for each individual asset
     */
    function areReservedBack(address[] calldata asset) external view returns (bool, bool[] memory);
}
