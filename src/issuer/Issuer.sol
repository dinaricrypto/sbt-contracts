// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/AccessControlDefaultAdminRulesUpgradeable.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import "./IOrderBridge.sol";
import "../IOrderFees.sol";

/// @notice Base contract managing orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/issuer/Issuer.sol)
abstract contract Issuer is
    Initializable,
    UUPSUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable,
    Multicall,
    IOrderBridge
{
    error ZeroAddress();
    error Paused();

    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees orderFees);
    event OrdersPaused(bool paused);

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAYMENTTOKEN_ROLE = keccak256("PAYMENTTOKEN_ROLE");
    bytes32 public constant ASSETTOKEN_ROLE = keccak256("ASSETTOKEN_ROLE");

    address public treasury;

    IOrderFees public orderFees;

    uint256 public numOpenOrders;

    bool public ordersPaused;

    function initialize(address owner, address treasury_, IOrderFees orderFees_) external initializer {
        __AccessControlDefaultAdminRules_init_unchained(0, owner);
        _grantRole(ADMIN_ROLE, owner);

        if (treasury_ == address(0)) revert ZeroAddress();

        treasury = treasury_;
        orderFees = orderFees_;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}

    modifier whenOrdersNotPaused() {
        if (ordersPaused) revert Paused();
        _;
    }

    function setTreasury(address account) external onlyRole(ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddress();

        treasury = account;
        emit TreasurySet(account);
    }

    function setOrderFees(IOrderFees fees) external onlyRole(ADMIN_ROLE) {
        orderFees = fees;
        emit OrderFeesSet(fees);
    }

    function setOrdersPaused(bool pause) external onlyRole(ADMIN_ROLE) {
        ordersPaused = pause;
        emit OrdersPaused(pause);
    }

    function getFeesForOrder(address assetToken, bool sell, uint256 amount) public view returns (uint256) {
        return address(orderFees) == address(0) ? 0 : orderFees.feesForOrder(assetToken, sell, amount);
    }
}
