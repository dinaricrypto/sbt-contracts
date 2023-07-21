// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.19;

/**
 * @title IProofOfReserveExecutor
 * @dev This interface represents the functions of the ProofOfReserveExecutor contract.
 */
interface IProofOfReserveExecutor {
    /**
     * @dev emitted when new asset is enabled or disabled
     * @param asset the address of the asset
     * @param enabled whether it was enabled or disabled
     */
    event AssetStateChanged(address indexed asset, bool enabled);
    /**
     * @dev Returns the list of assets
     * @return Array of asset addresses
     */

    function getAssets() external view returns (address[] memory);

    /**
     * @dev Enable a list of assets to be checked for reserve proof
     * @param assets The list of asset addresses to enable
     */
    function enableAssets(address[] memory assets) external;

    /**
     * @dev Disable a list of assets from being checked for reserve proof
     * @param assets The list of asset addresses to disable
     */
    function disableAssets(address[] memory assets) external;

    /**
     * @dev Checks whether all enabled assets are fully backed
     * @return True if all enabled assets are fully backed, false otherwise
     */
    function areAllAssetsBacked() external view returns (bool);
}
