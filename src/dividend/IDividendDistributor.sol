// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IDividendDistributor {
    function nextDistributionId() external returns (uint256);
    function createDistribution(address token, uint256 totalDistribution, uint256 endTime)
        external
        returns (uint256 distributionId);
    function distribute(uint256 _distributionId, address _recipient, uint256 _amount) external;
    function reclaimDistribution(uint256 _distributionId) external;
}
