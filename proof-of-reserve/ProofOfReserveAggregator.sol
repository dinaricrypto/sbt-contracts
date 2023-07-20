// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "./interfaces/IProofOfReserveAggregator.sol";

contract ProofOfReserveAggregator is IProofOfReserveAggregator {
    function enableProofOfReserveFeed(address asset, address feed) external override {}

    function disableProofOfReserveFeed(address asset) external override {}

    function getProofOfReserveFeedForAsset(address asset) external view override returns (address) {}

    function areReservedBack(address[] calldata asset) external override returns (bool, bool[] memory) {}
}