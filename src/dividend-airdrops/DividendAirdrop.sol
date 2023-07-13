// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

contract DividendAirdrop is Ownable {
    using SafeERC20 for IERC20;

    /// ------------------- Types ------------------- /// 

    // Struct to store information about each airdrop.
    struct Airdrop {
        bytes32 merkleRoot; // The Merkle root associated with the airdrop.
        uint256 remainingDistribution; // The amount of tokens remaining to be claimed.
        uint256 endTime; // The timestamp when the airdrop stops
        bool isReclaimed; // A flag indicating whether the airdrop has been reclaimed by the distributor.
    }

    // Event emitted when the claim window duration is updated.
    event ClaimWindowSet(uint256 newClaimWindow);

    // Event emitted when tokens are claimed from an airdrop.
    event Claimed(uint256 airdropId, address indexed account, uint256 amount);

    event NewAirdropCreated(uint256 airdropId, uint256 totalDistribution, uint256 startDate, uint256 endDate);

    event AirdropReclaimed(uint256 airdropId, uint256 totalReclaimed);

    // Custom errors
    error AlreadyClaimed(); // Error thrown when tokens have already been claimed for an airdrop.
    error AirdropStillRunning(); // Error thrown when trying to reclaim tokens from an airdrop that is still running.
    error AirdropEnded(); // Error thrown when trying to claim tokens from an airdrop that has ended.
    error InvalidProof(); // Error thrown when the provided Merkle proof is invalid.
    error AlreadyReclaimed(); // Error thrown when

    /// ------------------- Immuables ------------------- ///

    // The token address that will be used for the dividends.
    address public immutable token;

    /// ------------------- State ------------------- ///

    // The time window during which an airdrop can be claimed.
    uint256 public claimWindow;

    // Mapping to store the information of each airdrop by its ID.
    mapping(uint256 => Airdrop) public airdrops;

    // Nested mapping to store whether a specific address has claimed tokens in a specific airdrop.
    mapping(uint256 => mapping(address => bool)) public claimed;

    uint256 public nextAirdropId;

    /// ------------------- Initialization ------------------- ///

    /**
     * @dev Initializes the contract with token address, distributor address, and claim window.
     * @param _token The address of the token to be distributed.
     * @param _claimWindow The time window for claiming the airdrop.
     */
    constructor(address _token, uint256 _claimWindow) {
        token = _token;
        claimWindow = _claimWindow;
    }

    /// ------------------- Adminitration ------------------- ///

    /**
     * @notice Sets the claim window.
     * @dev Can only be called by the contract owner.
     * @param _newClaimWindow The new claim window in seconds.
     */
    function setClaimWindow(uint256 _newClaimWindow) external onlyOwner {
        claimWindow = _newClaimWindow;
        emit ClaimWindowSet(_newClaimWindow);
    }

    /// ------------------- Airdrop Lifecycle ------------------- ///

    /**
     * @notice Creates a new airdrop.
     * @dev Only the distributor can create a new airdrop.
     * @param _merkleRoot The Merkle root of the airdrop.
     * @param _totalDistribution The total amount of tokens to be distributed.
     */
    function createAirdrop(bytes32 _merkleRoot, uint256 _totalDistribution) external onlyOwner returns (uint256 airdropId) {
        // Load the next airdrop id into memory and increment it for the next time
        airdropId = nextAirdropId++;

        // Create a new airdrop and store it with the next available ID
        airdrops[airdropId] = Airdrop(_merkleRoot, _totalDistribution, block.timestamp + claimWindow, false);

        // Emit an event for the new airdrop
        emit NewAirdropCreated(airdropId, _totalDistribution, block.timestamp, block.timestamp + claimWindow);

        // Transfer the tokens for distribution from the distributor to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), _totalDistribution);
    }

    /**
     * @notice Allows a user to claim tokens from an airdrop if they are eligible.
     * @param _airdropId The ID of the airdrop.
     * @param _amount The amount of tokens the user is claiming.
     * @param proof The merkle proof for verification.
     */
    function claim(uint256 _airdropId, uint256 _amount, bytes32[] memory proof) external {
        // Check if the tokens have already been claimed by this user.
        if (claimed[_airdropId][msg.sender]) revert AlreadyClaimed();

        // Check if the airdrop has ended.
        if (block.timestamp > airdrops[_airdropId].endTime) revert AirdropEnded();

        // Compute the leaf node from the user's address and amount.
        bytes32 valueToProve = hashLeaf(msg.sender, _amount);
        // Verify the merkle proof.
        if (!MerkleProof.verify(proof, airdrops[_airdropId].merkleRoot, valueToProve)) revert InvalidProof();

        // Mark the tokens as claimed for this user.
        claimed[_airdropId][msg.sender] = true;

        // Update the total claimed tokens for this airdrop.
        airdrops[_airdropId].remainingDistribution -= _amount;

        // Emit an event for the claimed tokens.
        emit Claimed(_airdropId, msg.sender, _amount);

        // Transfer the tokens to the user.
        IERC20(token).safeTransfer(msg.sender, _amount);
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
     * @notice Reclaims unclaimed tokens from an airdrop.
     * @param _airdropId The ID of the airdrop to reclaim tokens from.
     * @dev Can only be called by the distributor after the claim window has passed.
     */
    function reclaimedAirdrop(uint256 _airdropId) external onlyOwner {
        if (airdrops[_airdropId].isReclaimed) revert AlreadyReclaimed();
        if (block.timestamp < airdrops[_airdropId].endTime) revert AirdropStillRunning();

        // Mark the airdrop as reclaimed
        airdrops[_airdropId].isReclaimed = true;
        emit AirdropReclaimed(_airdropId, airdrops[_airdropId].remainingDistribution);
        // Transfer the unclaimed tokens back to the distributor
        IERC20(token).safeTransfer(msg.sender, airdrops[_airdropId].remainingDistribution);
    }
}
