// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Interface for the extended functionalities of DividendDistribution contract
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/dividend/IDividendDistributor.sol)
interface IDividendDistributor {
    /**
     * @notice Fetches the ID for the next distribution.
     * @return The ID for the next distribution.
     */
    function nextDistributionId() external returns (uint256);
    /**
     * @notice Creates a new distribution.
     * @param token The address of the token to be distributed.
     * @param totalDistribution The total amount of tokens to be distributed.
     * @param endTime The timestamp when the distribution stops.
     * @dev Only the owner can create a new distribution.
     */
    function createDistribution(address token, uint256 totalDistribution, uint256 endTime)
        external
        returns (uint256 distributionId);
    /**
     * @notice Distributes tokens to recipient.
     * @param _distributionId The ID of the distribution.
     * @param _recipient The address of the user claiming tokens.
     * @param _amount The amount of tokens the user is claiming.
     * @dev Can only be called by the owner.
     */
    function distribute(uint256 _distributionId, address _recipient, uint256 _amount) external;
    /**
     * @notice Reclaims unclaimed tokens from an distribution.
     * @param _distributionId The ID of the distribution to reclaim tokens from.
     * @dev Can only be called by the distributor after the claim window has passed.
     */
    function reclaimDistribution(uint256 _distributionId) external;

    /**
     * @notice Mint tokens for a brokerage dividend to a target address
     * @param token Token address to mint (vUSD or DShare)
     * @param amount Amount to mint
     * @param target Address receiving minted tokens (contract for omnibus, or user wallet for individual brokerage)
     * @param brokerageDividendId Unique brokerage dividend ID for idempotency
     */
    function mintDividend(address token, uint256 amount, address target, bytes32 brokerageDividendId) external;

    /**
     * @notice Send distribution tokens to a recipient from contract balance
     * @param token Token address (vUSD or DShare)
     * @param amount Amount to send
     * @param recipient Address receiving tokens
     * @param distributionId Unique distribution ID for idempotency
     */
    function sendDistribution(address token, uint256 amount, address recipient, bytes32 distributionId) external;

    /**
     * @notice Send withholding tokens to a recipient from contract balance
     * @param token Token address (vUSD)
     * @param amount Amount to send
     * @param recipient Withholder address
     * @param withholdingId Unique withholding ID for idempotency
     */
    function sendWithholding(address token, uint256 amount, address recipient, bytes32 withholdingId) external;

    /**
     * @notice Send fee tokens to a revenue vault from contract balance
     * @param token Token address (vUSD)
     * @param amount Fee amount to send
     * @param recipient Revenue vault address
     * @param feeId Unique fee ID for idempotency
     */
    function sendFee(address token, uint256 amount, address recipient, bytes32 feeId) external;
}
