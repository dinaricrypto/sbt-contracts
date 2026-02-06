// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {ControlledUpgradeable} from "../deployment/ControlledUpgradeable.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDividendDistributor} from "./IDividendDistributor.sol";
import {IDShare} from "../IDShare.sol";

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

    event DividendMinted(
        bytes32 indexed brokerageDividendId, address indexed target, address indexed token, uint256 amount
    );

    event DistributionSent(
        bytes32 indexed distributionId, address indexed recipient, address indexed token, uint256 amount
    );

    event WithholdingSent(
        bytes32 indexed withholdingId, address indexed recipient, address indexed token, uint256 amount
    );

    event FeeSent(bytes32 indexed feeId, address indexed recipient, address indexed token, uint256 amount);

    // Custom errors
    error EndTimeBeforeMin(); // Error thrown when endtime is prior to minDistributionTime from now.
    error DistributionRunning(); // Error thrown when trying to reclaim tokens from an distribution that is still running.
    error DistributionEnded(); // Error thrown when trying to claim tokens from an distribution that has ended.
    error NotReclaimable(); // Error thrown when the distribution has already been reclaimed or does not exist.
    error DividendAlreadyMinted(bytes32 brokerageDividendId);
    error DistributionAlreadySent(bytes32 distributionId);
    error WithholdingAlreadySent(bytes32 withholdingId);
    error FeeAlreadySent(bytes32 feeId);
    error ZeroAddress();
    error ZeroAmount();

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

    /// @notice Tracks processed brokerage dividend IDs for idempotency
    mapping(bytes32 => bool) public dividendMinted;

    /// @notice Tracks processed distribution IDs for idempotency
    mapping(bytes32 => bool) public distributionSent;

    /// @notice Tracks processed withholding IDs for idempotency
    mapping(bytes32 => bool) public withholdingSent;

    /// @notice Tracks processed fee IDs for idempotency
    mapping(bytes32 => bool) public feeSent;

    /// ------------------- Version ------------------- ///
    function version() public view override returns (uint8) {
        return 2;
    }

    function publicVersion() public view override returns (string memory) {
        return "2.0.0";
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

    /// ------------------- Dividend Minting ------------------- ///

    /// @notice Mint tokens for a brokerage dividend to a target address
    /// @param token Token address to mint (vUSD or DShare)
    /// @param amount Amount to mint
    /// @param target Address receiving minted tokens (this contract for omnibus, or user wallet for individual brokerage)
    /// @param brokerageDividendId Unique brokerage dividend ID for idempotency
    function mintDividend(address token, uint256 amount, address target, bytes32 brokerageDividendId)
        external
        onlyRole(DISTRIBUTOR_ROLE)
    {
        if (dividendMinted[brokerageDividendId]) revert DividendAlreadyMinted(brokerageDividendId);
        if (token == address(0)) revert ZeroAddress();
        if (target == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        dividendMinted[brokerageDividendId] = true;

        emit DividendMinted(brokerageDividendId, target, token, amount);

        IDShare(token).mint(target, amount);
    }

    /// ------------------- Distribution Sends ------------------- ///

    /// @notice Send distribution tokens to a recipient from contract balance
    /// @param token Token address (vUSD or DShare)
    /// @param amount Amount to send
    /// @param recipient Address receiving tokens
    /// @param distributionId Unique distribution ID for idempotency
    function sendDistribution(address token, uint256 amount, address recipient, bytes32 distributionId)
        external
        onlyRole(DISTRIBUTOR_ROLE)
    {
        if (distributionSent[distributionId]) revert DistributionAlreadySent(distributionId);
        if (token == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        distributionSent[distributionId] = true;

        emit DistributionSent(distributionId, recipient, token, amount);

        IERC20(token).safeTransfer(recipient, amount);
    }

    /// @notice Send withholding tokens to a recipient from contract balance
    /// @param token Token address (vUSD)
    /// @param amount Amount to send
    /// @param recipient Withholder address
    /// @param withholdingId Unique withholding ID for idempotency
    function sendWithholding(address token, uint256 amount, address recipient, bytes32 withholdingId)
        external
        onlyRole(DISTRIBUTOR_ROLE)
    {
        if (withholdingSent[withholdingId]) revert WithholdingAlreadySent(withholdingId);
        if (token == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        withholdingSent[withholdingId] = true;

        emit WithholdingSent(withholdingId, recipient, token, amount);

        IERC20(token).safeTransfer(recipient, amount);
    }

    /// @notice Send fee tokens to a revenue vault from contract balance
    /// @param token Token address (vUSD)
    /// @param amount Fee amount to send
    /// @param recipient Revenue vault address
    /// @param feeId Unique fee ID for idempotency
    function sendFee(address token, uint256 amount, address recipient, bytes32 feeId)
        external
        onlyRole(DISTRIBUTOR_ROLE)
    {
        if (feeSent[feeId]) revert FeeAlreadySent(feeId);
        if (token == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        feeSent[feeId] = true;

        emit FeeSent(feeId, recipient, token, amount);

        IERC20(token).safeTransfer(recipient, amount);
    }
}
