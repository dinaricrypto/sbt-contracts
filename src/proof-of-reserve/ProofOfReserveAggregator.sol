// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/IProofOfReserveAggregator.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title ProofOfReserveAggregator
 * @dev This contract acts as a decentralized aggregator of proof of reserve data.
 * It uses Chainlink price feed oracles to determine whether certain assets are fully reserved.
 * Only the contract owner can enable or disable feeds for different assets.
 */
contract ProofOfReserveAggregator is IProofOfReserveAggregator, Ownable {
    // Mapping from asset addresses to Chainlink oracle feed addresses
    mapping(address => address) internal _proofOfReserveList;

    // Error when the address of the asset is the zero address
    error InvalidAsset();
    // Error when the address of the feed is the zero address
    error InvalidFeed();
    // Error when a feed is already enabled for the asset
    error FeedAlreadyEnabled();

    /**
     * @dev Enable a Chainlink oracle feed for an asset
     * @param asset The address of the asset
     * @param feed The address of the Chainlink oracle feed
     */
    function enableProofOfReserveFeed(address asset, address feed) external override onlyOwner {
        if (asset == address(0)) revert InvalidAsset();
        if (feed == address(0)) revert InvalidFeed();
        if (_proofOfReserveList[asset] != address(0)) revert FeedAlreadyEnabled();

        emit ProofOfReserveFeedStateChanged(asset, feed, true);

        _proofOfReserveList[asset] = feed;
    }

    /**
     * @dev Disable the Chainlink oracle feed for an asset
     * @param asset The address of the asset
     */
    function disableProofOfReserveFeed(address asset) external override onlyOwner {
        emit ProofOfReserveFeedStateChanged(asset, address(0), false);
        delete _proofOfReserveList[asset];
    }

    /**
     * @dev Get the Chainlink oracle feed for an asset
     * @param asset The address of the asset
     * @return The address of the Chainlink oracle feed for the asset
     */
    function getProofOfReserveFeedForAsset(address asset) external view override returns (address) {
        return _proofOfReserveList[asset];
    }

    /**
     * @dev Check whether the reserves for a list of assets are fully backed
     * @param asset The list of asset addresses
     * @return The overall reserve status and a list of flags for each individual asset
     */
    function areReservedBack(address[] calldata asset) external view override returns (bool, bool[] memory) {
        bool[] memory unbackedAssetsFlags = new bool[](asset.length);
        bool areReservesBacked = true;

        unchecked {
            for (uint256 i; i < asset.length; i++) {
                address assetAddress = asset[i];
                address feed = _proofOfReserveList[assetAddress];
                if (feed != address(0)) {
                    (, int256 answer,,,) = AggregatorV3Interface(feed).latestRoundData();
                    if (answer < 0) {
                        unbackedAssetsFlags[i] = true;
                        areReservesBacked = false;
                    }
                }
            }
        }
        return (areReservesBacked, unbackedAssetsFlags);
    }
}
