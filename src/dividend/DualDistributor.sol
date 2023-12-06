// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {AccessControlDefaultAdminRules} from
    "openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDividendDistributor} from "./IDividendDistributor.sol";

/**
 * @title DualDistributor Contract
 * @notice A contract to manage the distribution of dividends for both USDC and DShare.
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/dividend/DualDistributor.sol)
 */
contract DualDistributor is AccessControlDefaultAdminRules {
    using SafeERC20 for IERC20;

    event NewDistribution(
        uint256 indexed distributionId, address indexed DShare, uint256 usdcAmount, uint256 dShareAmount
    );

    event NewDividendDistributionSet(address indexed newDivividendDistribution);

    error ZeroAddress();

    /// @notice Role for approved distributors
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    /// @dev Address of the dividend distribution contract.
    address public dividendDistribution;

    /// @dev Mapping to store the relationship between DShare and XdShare.
    mapping(address DShare => address XdShare) public dShareToXdShare;

    /**
     * @notice Initializes the `DualDistributor` contract.
     * @param owner The address of the owner/administrator.
     * @param _dividendDistribution The address of the dividend distribution contract.
     */
    constructor(address owner, address _dividendDistribution) AccessControlDefaultAdminRules(0, owner) {
        dividendDistribution = _dividendDistribution;
    }

    /**
     * @notice Updates the address of the dividend distribution contract.
     * @param _dividendDistribution The new address for dividend distribution.
     */
    function setDividendDistribution(address _dividendDistribution) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_dividendDistribution == address(0)) revert ZeroAddress();
        dividendDistribution = _dividendDistribution;
        emit NewDividendDistributionSet(_dividendDistribution);
    }

    /**
     * @notice Adds a new pair of DShare and XdShare addresses.
     * @param _dShare Address of the DShare token.
     * @param _XdShare Address of the XdShare token.
     */
    function setXdShareForDShare(address _dShare, address _XdShare) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_dShare == address(0)) revert ZeroAddress();
        dShareToXdShare[_dShare] = _XdShare;
    }

    /**
     * @notice Distributes dividends to DShare and XdShare holders.
     * @dev Requires the distributor role and XdShare to be locked.
     * @param stableCoin Address of the stable coin to distribute.
     * @param dShare Address of the DShare token.
     * @param stableCoinAmount Amount of stable coin to distribute.
     * @param dShareAmount Amount of DShare tokens to distribute.
     * @param endTime The timestamp when the distribution stops.
     */
    function distribute(
        address stableCoin,
        address dShare,
        uint256 stableCoinAmount,
        uint256 dShareAmount,
        uint256 endTime
    ) external onlyRole(DISTRIBUTOR_ROLE) returns (uint256) {
        if (stableCoin == address(0)) revert ZeroAddress();
        address XdShare = dShareToXdShare[dShare];
        if (XdShare == address(0)) revert ZeroAddress();

        emit NewDistribution(
            IDividendDistributor(dividendDistribution).nextDistributionId(), dShare, stableCoinAmount, dShareAmount
        );

        IERC20(dShare).safeTransfer(XdShare, dShareAmount);
        IERC20(stableCoin).safeIncreaseAllowance(dividendDistribution, stableCoinAmount);
        return IDividendDistributor(dividendDistribution).createDistribution(stableCoin, stableCoinAmount, endTime);
    }
}
