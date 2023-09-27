// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AccessControlDefaultAdminRules} from "openzeppelin-contracts/contracts/access/AccessControlDefaultAdminRules.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IxdShare} from "../IxdShare.sol";
import {IDividendDistributor} from "./IDividendDistributor.sol";

/**
 * @title DualDistributor Contract
 * @notice A contract to manage the distribution of dividends for both USDC and dShare.
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/dividend/DualDistributor.sol)
 */
contract DualDistributor is AccessControlDefaultAdminRules {
    using SafeERC20 for IERC20;

    event NewDistribution(uint256 distributionId, address indexed dShare, uint256 usdcAmount, uint256 dShareAmount);

    error ZeroAddress();
    error XdshareIsNotLocked();

    /// @notice Role for approved distributors
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    /// @dev Address of the USDC token.
    address public USDC;

    /// @dev Address of the dividend distribution contract.
    address public dividendDistrubtion;

    /// @dev Mapping to store the relationship between dShare and xdShare.
    mapping(address dShare => address xdShare) public dShareToXdShare;

    /**
     * @notice Initializes the `DualDistributor` contract.
     * @param owner The address of the owner/administrator.
     * @param _USDC The address of the USDC token.
     * @param _dividendDistrubtion The address of the dividend distribution contract.
     */
    constructor(address owner, address _USDC, address _dividendDistrubtion) AccessControlDefaultAdminRules(0, owner) {
        USDC = _USDC;
        dividendDistrubtion = _dividendDistrubtion;
    }

    /**
     * @notice Updates the USDC token address.
     * @param _USDC The new address for the USDC token.
     */
    function setUSDC(address _USDC) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_USDC == address(0)) revert ZeroAddress();
        USDC = _USDC;
    }

    /**
     * @notice Updates the address of the dividend distribution contract.
     * @param _dividendAddress The new address for dividend distribution.
     */
    function setNewDividendAddress(address _dividendAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_dividendAddress == address(0)) revert ZeroAddress();
        dividendDistrubtion = _dividendAddress;
    }

    /**
     * @notice Adds a new pair of dShare and xdShare addresses.
     * @param _dShare Address of the dShare token.
     * @param _xdShare Address of the xdShare token.
     */
    function addDShareXdSharePair(address _dShare, address _xdShare) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_dShare == address(0) || _xdShare == address(0)) revert ZeroAddress();
        dShareToXdShare[_dShare] = _xdShare;
    }

    /**
     * @notice Distributes dividends to dShare and xdShare holders.
     * @dev Requires the distributor role and xdShare to be locked.
     * @param dShare Address of the dShare token.
     * @param usdcAmount Amount of USDC to distribute.
     * @param dShareAmount Amount of dShare tokens to distribute.
     * @param endTime The timestamp when the distribution stops.
     */
    function distribute(address dShare, uint256 usdcAmount, uint256 dShareAmount, uint256 endTime)
        external
        onlyRole(DISTRIBUTOR_ROLE)
    {
        address xdShare = dShareToXdShare[dShare];
        if (xdShare == address(0)) revert ZeroAddress();
        if (!IxdShare(xdShare).isLocked()) revert XdshareIsNotLocked();
        
        emit NewDistribution(
            IDividendDistributor(dividendDistrubtion).nextDistributionId(), dShare, usdcAmount, dShareAmount
        );

        IERC20(dShare).safeTransfer(xdShare, dShareAmount);
        IERC20(USDC).safeApprove(dividendDistrubtion, usdcAmount);
        IDividendDistributor(dividendDistrubtion).createDistribution(USDC, usdcAmount, endTime);
    }
}
