// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {dShare} from "../dShare.sol";
import {ITransferRestrictor} from "../ITransferRestrictor.sol";
import {ERC4626, SafeTransferLib} from "solady/src/tokens/ERC4626.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title xdShare Contract
 * @dev This contract acts as a wrapper over the dShare token, providing additional functionalities.
 *      It serves as a reinvestment token that uses dShare as the underlying token.
 *      Additionally, it employs the ERC4626 standard for its operations.
 *      If TokenManager is not used, make sure that dShare will never split.
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/xdShare.sol)
 */
// slither-disable-next-line missing-inheritance
contract xdShare is Initializable, ERC4626, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /// ------------------- Types ------------------- ///

    using SafeERC20 for IERC20;

    error ZeroAddress();

    /// ------------------- State ------------------- ///

    struct xdShareStorage {
        dShare _underlyingDShare;
        string _name;
        string _symbol;
    }

    // keccak256(abi.encode(uint256(keccak256("dinaricrypto.storage.xdShare")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant xdShareStorageLocation = 0xc68f8eaf252bfabfa8dbc02d218f101ac0ca40c3b47f9845899753284dbfb400;

    function _getxdShareStorage() private pure returns (xdShareStorage storage $) {
        assembly {
            $.slot := xdShareStorageLocation
        }
    }

    /// ------------------- Initialization ------------------- ///

    function initialize(dShare dShare_, string memory name_, string memory symbol_) public initializer {
        __Ownable_init_unchained(msg.sender);
        __ReentrancyGuard_init_unchained();

        if (address(dShare_) == address(0)) revert ZeroAddress();

        xdShareStorage storage $ = _getxdShareStorage();
        $._underlyingDShare = dShare_;
        $._name = name_;
        $._symbol = symbol_;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// ------------------- Getters ------------------- ///
    /**
     * @dev Returns the name of the xdShare token.
     * @return A string representing the name.
     */
    function name() public view override returns (string memory) {
        xdShareStorage storage $ = _getxdShareStorage();
        return $._name;
    }

    /**
     * @dev Returns the symbol of the xdShare token.
     * @return A string representing the symbol.
     */
    function symbol() public view override returns (string memory) {
        xdShareStorage storage $ = _getxdShareStorage();
        return $._symbol;
    }

    /**
     * @dev Returns the address of the underlying asset.
     * @return The address of the underlying dShare token.
     */
    function asset() public view override returns (address) {
        xdShareStorage storage $ = _getxdShareStorage();
        return address($._underlyingDShare);
    }

    /// ------------------- Transfer Restrictions ------------------- ///

    /**
     * @dev Hook that is called before any token transfer. This includes minting and burning.
     * @param from Address of the sender.
     * @param to Address of the receiver.
     */
    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        // Apply underlying transfer restrictions to this vault token.
        xdShareStorage storage $ = _getxdShareStorage();
        ITransferRestrictor restrictor = $._underlyingDShare.transferRestrictor();
        if (address(restrictor) != address(0)) {
            restrictor.requireNotRestricted(from, to);
        }
    }

    function isBlacklisted(address account) external view returns (bool) {
        xdShareStorage storage $ = _getxdShareStorage();
        ITransferRestrictor restrictor = $._underlyingDShare.transferRestrictor();
        if (address(restrictor) == address(0)) return false;
        return restrictor.isBlacklisted(account);
    }
}
