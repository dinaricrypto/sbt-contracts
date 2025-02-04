// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {ControlledUpgradeable} from "../deployment/ControlledUpgradeable.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDividendDistributor} from "./IDividendDistributor.sol";

/// @notice Distributes tokens to users over time.
/// @dev This contract allows a DISTRIBUTOR_ROLE to create a distribution of tokens to users.
/// It is intended as a flexible way to handle payouts while recording those payouts on-chain.
/// A distribution is created with a pool of tokens and an end time.
/// A DISTRIBUTOR_ROLE can then distribute from that pool to users until the end time.
/// After the end time, the DISTRIBUTOR_ROLE can reclaim any remaining tokens.
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/dividend/DividendDistribution.sol)
contract DividendDistribution is ControlledUpgradeable, IDividendDistributor {
    using SafeERC20 for IERC20;

    /// ------------------- Types ------------------- ///

    // Struct to store information about each distribution.
    struct Distribution {
        address token; // The address of the token to be distributed.
        uint256 remainingDistribution; // The amount of tokens remaining to be claimed.
        uint256 endTime; // The timestamp when the distribution stops
    }

    event MinDistributionTimeSet(uint64 minDistributionTime);

    // Event emitted when tokens are claimed from an distribution.
    event Distributed(uint256 indexed distributionId, address indexed account, uint256 amount);

    event NewDistributionCreated(
        uint256 indexed distributionId, uint256 totalDistribution, uint256 startDate, uint256 endDate
    );

    event DistributionReclaimed(uint256 indexed distributionId, uint256 totalReclaimed);

    // Custom errors
    error EndTimeBeforeMin(); // Error thrown when endtime is prior to minDistributionTime from now.
    error DistributionRunning(); // Error thrown when trying to reclaim tokens from an distribution that is still running.
    error DistributionEnded(); // Error thrown when trying to claim tokens from an distribution that has ended.
    error NotReclaimable(); // Error thrown when the distribution has already been reclaimed or does not exist.

    /// ------------------ Constants ------------------ ///

    /// @notice Role for approved distributors
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    /// ------------------- State ------------------- ///

    // Mapping to store the information of each distribution by its ID.
    mapping(uint256 => Distribution) public distributions;

    /// @notice The next distribution ID to be used.
    uint256 public nextDistributionId;

    /// @notice The minimum time that must pass between the creation of a distribution and its end time.
    uint64 public minDistributionTime = 1 days;

    /// ------------------- Version ------------------- ///
    function version() public view override returns (uint8) {
        return 1;
    }

    function publicVersion() public view override returns (string memory) {
        return "1.0.0";
    }

    /// ------------------- Initialization ------------------- ///

    function initialize(address owner, address upgrader) public reinitializer(version()) {
        __ControlledUpgradeable_init(owner, upgrader);
    }

    /// @notice Set the minimum time that must pass between the creation of a distribution and its end time.
    function setMinDistributionTime(uint64 _minDistributionTime) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minDistributionTime = _minDistributionTime;
        emit MinDistributionTimeSet(_minDistributionTime);
    }

    /// ------------------- Distribution Lifecycle ------------------- ///

    /// @inheritdoc IDividendDistributor
    function createDistribution(address token, uint256 totalDistribution, uint256 endTime)
        external
        onlyRole(DISTRIBUTOR_ROLE)
        returns (uint256 distributionId)
    {
        // Check if the endtime is in the past.
        if (endTime <= block.timestamp + minDistributionTime) revert EndTimeBeforeMin();

        // Load the next distribution id into memory and increment it for the next time
        distributionId = nextDistributionId++;

        // Create a new distribution and store it with the next available ID
        distributions[distributionId] = Distribution(token, totalDistribution, endTime);

        // Emit an event for the new distribution
        emit NewDistributionCreated(distributionId, totalDistribution, block.timestamp, endTime);

        // Transfer the tokens for distribution from the distributor to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), totalDistribution);
    }

    /// @inheritdoc IDividendDistributor
    function distribute(uint256 _distributionId, address _recipient, uint256 _amount)
        external
        onlyRole(DISTRIBUTOR_ROLE)
    {
        // Check if the distribution has ended.
        if (block.timestamp > distributions[_distributionId].endTime) revert DistributionEnded();

        // Update the total claimed tokens for this distribution.
        distributions[_distributionId].remainingDistribution -= _amount;

        // Emit an event for the claimed tokens.
        emit Distributed(_distributionId, _recipient, _amount);

        // Transfer the tokens to the user.
        IERC20(distributions[_distributionId].token).safeTransfer(_recipient, _amount);
    }

    /// @inheritdoc IDividendDistributor
    function reclaimDistribution(uint256 _distributionId) external onlyRole(DISTRIBUTOR_ROLE) {
        uint256 endTime = distributions[_distributionId].endTime;
        if (endTime == 0) revert NotReclaimable();
        if (block.timestamp < endTime) revert DistributionRunning();

        uint256 totalReclaimed = distributions[_distributionId].remainingDistribution;

        address token = distributions[_distributionId].token;
        delete distributions[_distributionId];

        emit DistributionReclaimed(_distributionId, totalReclaimed);

        // Transfer the unclaimed tokens back to the distributor
        IERC20(token).safeTransfer(msg.sender, totalReclaimed);
    }
}
