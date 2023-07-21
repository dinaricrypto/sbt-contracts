// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.19;

import {IProofOfReserveExecutor} from "./interfaces/IProofOfReserveExecutor.sol";
import {IProofOfReserveAggregator} from "./interfaces/IProofOfReserveAggregator.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title ProofOfReserveExecutor
 * @dev This contract manages a list of assets to be checked for reserve proof.
 * It uses the ProofOfReserveAggregator to determine whether the reserves for the assets are fully backed.
 */
contract ProofOfReserveExecutor is IProofOfReserveExecutor, Ownable {
    // Instance of the ProofOfReserveAggregator contract
    IProofOfReserveAggregator internal immutable _proofOfReserveAggregator;

    // List of asset addresses
    address[] internal _assets;

    // Mapping from asset addresses to whether the asset is enabled
    mapping(address => bool) internal _assetState;

    /**
     * @dev Sets the address of the ProofOfReserveAggregator contract
     * @param _aggregator The address of the ProofOfReserveAggregator contract
     */
    constructor(address _aggregator) {
        _proofOfReserveAggregator = IProofOfReserveAggregator(_aggregator);
    }

    /**
     * @dev Returns the list of assets
     * @return Array of asset addresses
     */
    function getAssets() external view override returns (address[] memory) {
        return _assets;
    }

    /**
     * @dev Enable a list of assets to be checked for reserve proof
     * @param assets The list of asset addresses to enable
     */
    function enableAssets(address[] memory assets) external override onlyOwner {
        for (uint256 i; i < assets.length; i++) {
            address asset = assets[i];
            if (_assetState[asset]) continue;
            _assets.push(asset);
       
            _assetState[asset] = true;
            emit AssetStateChanged(asset, true);
        }
        
    }

    /**
     * @dev Disable a list of assets from being checked for reserve proof
     * @param assets The list of asset addresses to disable
     */
    function disableAssets(address[] memory assets) external override onlyOwner {
        for (uint256 i; i < assets.length; i++) {
            if (_assetState[assets[i]]) {
                _deleteAssetFromArray(assets[i]);
                delete _assetState[assets[i]];
            }
        }
    }

    /**
     * @dev Deletes an asset from the list of assets
     * @param asset The address of the asset to delete
     */
    function _deleteAssetFromArray(address asset) internal {
        uint256 assetsLength = _assets.length;

        for (uint256 i = 0; i < assetsLength; ++i) {
            if (_assets[i] == asset) {
                if (i != assetsLength - 1) {
                    _assets[i] = _assets[assetsLength - 1];
                }

                _assets.pop();
                break;
            }
        }
    }

    /**
     * @dev Checks whether all enabled assets are fully backed
     * @return True if all enabled assets are fully backed, false otherwise
     */
    function areAllAssetsBacked() external view override returns (bool) {
        if (_assets.length == 0) {
            return true;
        }

        (bool areReservesBacked,) = _proofOfReserveAggregator.areReservedBack(_assets);

        return areReservesBacked;
    }
}
