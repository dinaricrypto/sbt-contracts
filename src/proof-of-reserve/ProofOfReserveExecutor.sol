// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IProofOfReserveExecutor} from "./interfaces/IProofOfReserveExecutor.sol";
import {IProofOfReserveAggregator} from "./interfaces/IProofOfReserveAggregator.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract ProofOfReserveExecutore is IProofOfReserveExecutor, Ownable {
    IProofOfReserveAggregator internal immutable _proofOfReserveAggregator;
    address[] internal _assets;

    mapping(address => bool) internal _assetState;

    constructor(address _aggregator) {
        _proofOfReserveAggregator = IProofOfReserveAggregator(_aggregator);
    }

    function getAssets() external view override returns (address[] memory) {
        return _assets;
    }

    function enableAssets(address[] memory assets) external override onlyOwner {
        for (uint256 i; i < assets.length; i++) {
            address asset = assets[i];
            if (_assetState[asset]) continue;
            _assets.push(asset);
            _assetState[asset] = true;
        }
    }

    function disableAssets(address[] memory assets) external override onlyOwner {
        for (uint256 i; i < assets.length; i++) {
            if (_assetState[assets[i]]) {
                _deleteAssetFromArray(assets[i]);
                delete _assetState[assets[i]];
            }
        }
    }

    /**
     * @dev delete asset from array.
     * @param asset the address to delete
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

    function areAllAssetsBacked() external view override returns (bool) {
        if (_assets.length == 0) {
            return true;
        }

        (bool areReservesBacked,) = _proofOfReserveAggregator.areReservedBack(_assets);

        return areReservesBacked;
    }
}
