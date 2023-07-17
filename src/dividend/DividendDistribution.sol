// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

contract DividendDistribution is Ownable {
    using SafeERC20 for IERC20;

    /// ------------------- Types ------------------- ///

    // Struct to store information about each distribution.
    struct Distribution {
        address token; // The address of the token to be distributed.
        bytes32 merkleRoot; // The Merkle root associated with the distribution.
        uint256 remainingDistribution; // The amount of tokens remaining to be claimed.
        uint256 endTime; // The timestamp when the distribution stops
    }

    // Event emitted when tokens are claimed from an distribution.
    event Distributed(uint256 indexed distributionId, address indexed account, uint256 amount);

    event NewDistributionCreated(
        uint256 indexed distributionId, uint256 totalDistribution, uint256 startDate, uint256 endDate
    );

    event DistributionReclaimed(uint256 indexed distributionId, uint256 totalReclaimed);

    // Custom errors
    error EndTimeInPast(); // Error thrown when endtime is in the past.
    error AlreadyClaimed(); // Error thrown when tokens have already been claimed for an distribution.
    error DistributionRunning(); // Error thrown when trying to reclaim tokens from an distribution that is still running.
    error DistributionEnded(); // Error thrown when trying to claim tokens from an distribution that has ended.
    error InvalidProof(); // Error thrown when the provided Merkle proof is invalid.
    error NotReclaimable(); // Error thrown when the distribution has already been reclaimed or does not exist.

    /// ------------------- State ------------------- ///

    // Mapping to store the information of each distribution by its ID.
    mapping(uint256 => Distribution) public distributions;

    // Nested mapping to store whether a specific address has claimed tokens in a specific distribution.
    mapping(uint256 => mapping(address => bool)) public claimed;

    uint256 public nextDistributionId;

    /// ------------------- Distribution Lifecycle ------------------- ///

    /**
     * @notice Creates a new distribution.
     * @param token The address of the token to be distributed.
     * @param merkleRoot The Merkle root of the distribution.
     * @param totalDistribution The total amount of tokens to be distributed.
     * @param endTime The timestamp when the distribution stops.
     * @dev Only the owner can create a new distribution.
     */
    function createDistribution(address token, bytes32 merkleRoot, uint256 totalDistribution, uint256 endTime)
        external
        onlyOwner
        returns (uint256 distributionId)
    {
        // Check if the endtime is in the past.
        if (endTime <= block.timestamp) revert EndTimeInPast();

        // Load the next distribution id into memory and increment it for the next time
        distributionId = nextDistributionId++;

        // Create a new distribution and store it with the next available ID
        distributions[distributionId] = Distribution(token, merkleRoot, totalDistribution, endTime);

        // Emit an event for the new distribution
        emit NewDistributionCreated(distributionId, totalDistribution, block.timestamp, endTime);

        // Transfer the tokens for distribution from the distributor to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), totalDistribution);
    }

    /**
     * @notice Allows a user to claim tokens from an distribution if they are eligible.
     * @param _distributionId The ID of the distribution.
     * @param _recipient The address of the user claiming tokens.
     * @param _amount The amount of tokens the user is claiming.
     * @param proof The merkle proof for verification.
     */
    function distribute(uint256 _distributionId, address _recipient, uint256 _amount, bytes32[] memory proof)
        external
        onlyOwner
    {
        // Check if the tokens have already been claimed by this user.
        if (claimed[_distributionId][_recipient]) revert AlreadyClaimed();

        // Check if the distribution has ended.
        if (block.timestamp > distributions[_distributionId].endTime) revert DistributionEnded();

        // Compute the leaf node from the user's address and amount.
        bytes32 valueToProve = hashLeaf(_recipient, _amount);

        // Verify the merkle proof.
        if (!MerkleProof.verify(proof, distributions[_distributionId].merkleRoot, valueToProve)) revert InvalidProof();

        // Mark the tokens as claimed for this user.
        claimed[_distributionId][_recipient] = true;

        // Update the total claimed tokens for this distribution.
        distributions[_distributionId].remainingDistribution -= _amount;

        // Emit an event for the claimed tokens.
        emit Distributed(_distributionId, _recipient, _amount);

        // Transfer the tokens to the user.
        IERC20(distributions[_distributionId].token).safeTransfer(_recipient, _amount);
    }

    /**
     * @notice Computes the hash of a merkle tree leaf node.
     * @param _user The address of the user.
     * @param _amount The amount of tokens the user is claiming.
     */
    function hashLeaf(address _user, uint256 _amount) public pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(abi.encodePacked(_user, _amount)))));
    }

    /**
     * @notice Reclaims unclaimed tokens from an distribution.
     * @param _distributionId The ID of the distribution to reclaim tokens from.
     * @dev Can only be called by the distributor after the claim window has passed.
     */
    function reclaimDistribution(uint256 _distributionId) external onlyOwner {
        uint256 endTime = distributions[_distributionId].endTime;
        if (endTime == 0) revert NotReclaimable();
        if (block.timestamp < endTime) revert DistributionRunning();

        uint256 totalReclaimed = distributions[_distributionId].remainingDistribution;
        emit DistributionReclaimed(_distributionId, totalReclaimed);

        address token = distributions[_distributionId].token;
        delete distributions[_distributionId];

        // Transfer the unclaimed tokens back to the distributor
        IERC20(token).safeTransfer(msg.sender, totalReclaimed);
    }
}
