// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AccessControlDefaultAdminRules} from
    "openzeppelin-contracts/contracts/access/AccessControlDefaultAdminRules.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IxdShare} from "../IxdShare.sol";
import {IDividendDistributor} from "./IDividendDistributor.sol";

contract DualDistributor is AccessControlDefaultAdminRules {
    using SafeERC20 for IERC20;

    event NewDistribution(uint256 distributionId, address indexed dShare, uint256 usdcAmount, uint256 dShareAmount);

    error ZeroAddress();
    error XdshareIsNotLocked();
    /// ------------------ Constants ------------------ ///

    /// @notice Role for approved distributors
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    /// ------------------- State ------------------- ///

    address public USDC;
    address public dividendDistrubtion;
    // Mapping to store the information of each pair dshare/xdshare
    mapping(address dShare => address xdShare) public dShareToXdShare;

    /// ------------------- Initialization ------------------- ///
    constructor(address owner, address _USDC, address _dividendDistrubtion) AccessControlDefaultAdminRules(0, owner) {
        USDC = _USDC;
        dividendDistrubtion = _dividendDistrubtion;
    }

    /// ------------------- Setter ------------------- ///

    function setUSDC(address _USDC) external onlyRole(DISTRIBUTOR_ROLE) {
        if (_USDC == address(0)) revert ZeroAddress();
        USDC = _USDC;
    }

    function setNewDividendAddress(address _dividendAddress) external onlyRole(DISTRIBUTOR_ROLE) {
        if (_dividendAddress == address(0)) revert ZeroAddress();
        dividendDistrubtion = _dividendAddress;
    }

    function addDShareXdSharePair(address _dShare, address _xdShare) external onlyRole(DISTRIBUTOR_ROLE) {
        if (_dShare == address(0) || _xdShare == address(0)) revert ZeroAddress();
        dShareToXdShare[_dShare] = _xdShare;
    }

    /// ------------------- Distribution Lifecycle ------------------- ///
    function distribute(address dShare, uint256 usdcAmount, uint256 dShareAmount, uint256 endTime)
        external
        onlyRole(DISTRIBUTOR_ROLE)
    {
        address xdShare = dShareToXdShare[dShare];
        if (xdShare == address(0)) revert ZeroAddress();
        if (!IxdShare(xdShare).isLocked()) revert XdshareIsNotLocked();
        IERC20(dShare).safeTransfer(xdShare, dShareAmount);
        IERC20(USDC).safeApprove(dividendDistrubtion, usdcAmount);
        uint256 distributionId = IDividendDistributor(dividendDistrubtion).createDistribution(USDC, usdcAmount, endTime);
        emit NewDistribution(distributionId, dShare, usdcAmount, dShareAmount);
    }
}
