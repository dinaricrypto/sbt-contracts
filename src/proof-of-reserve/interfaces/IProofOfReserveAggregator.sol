// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

interface IProofOfReserveAggregator {
    function getProofOfReserveFeedForAsset(address asset) external view returns (address);
    function enableProofOfReserveFeed(address asset, address feed) external;
    function disableProofOfReserveFeed(address asset) external;
    function areReservedBack(address[] calldata asset) external view returns (bool, bool[] memory);
}
