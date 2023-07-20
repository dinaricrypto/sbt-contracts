// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "./interfaces/IProofOfReserveAggregator.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract ProofOfReserveAggregator is IProofOfReserveAggregator, Ownable {
    mapping(address => address) internal _proofOfReserveList;

    error InvalidAsset();
    error InvalidFeed();
    error FeedAlreadyEnabled();

    function enableProofOfReserveFeed(address asset, address feed) external override onlyOwner {
        if (asset == address(0)) revert InvalidAsset();
        if (feed == address(0)) revert InvalidFeed();
        if (_proofOfReserveList[asset] != address(0)) revert FeedAlreadyEnabled();

        _proofOfReserveList[asset] = feed;
    }

    function disableProofOfReserveFeed(address asset) external override onlyOwner {
        delete _proofOfReserveList[asset];
    }

    function getProofOfReserveFeedForAsset(address asset) external view override returns (address) {
        return _proofOfReserveList[asset];
    }

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
