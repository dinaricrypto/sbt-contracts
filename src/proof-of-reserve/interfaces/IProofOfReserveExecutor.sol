// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

interface IProofOfReserveExecutor {
    function getAssets() external view returns (address[] memory);
    function enableAssets(address[] memory assets) external;
    function disableAssets(address[] memory assets) external;
    function areAllAssetsBacked() external view returns (bool);
}
