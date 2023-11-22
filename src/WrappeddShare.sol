// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {dShare} from "./dShare.sol";
import {ITransferRestrictor} from "./ITransferRestrictor.sol";
import {IWrappeddShare} from "./IWrappeddShare.sol";
import {ERC4626, SafeTransferLib} from "solady/src/tokens/ERC4626.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title WrappeddShare Contract
 * @dev An ERC4626 vault wrapper around the rebasing dShare token.
 *      It accumulates the value of rebases and yield distributions.
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/WrappeddShare.sol)
 */
contract WrappeddShare is IWrappeddShare, Initializable, ERC4626, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /// ------------------- Types ------------------- ///

    using SafeERC20 for IERC20;

    error IssuancePaused();

    event VaultLocked();
    event VaultUnlocked();

    /// ------------------- State ------------------- ///

    struct WrappeddShareStorage {
        dShare _underlyingDShare;
        bool _isLocked;
        string _name;
        string _symbol;
    }

    // keccak256(abi.encode(uint256(keccak256("dinaricrypto.storage.WrappeddShare")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WrappeddShareStorageLocation =
        0x152e99b50b5f6a0e49f31b9c18139e0eb82d89de09b8e6a3d245658cb9305300;

    function _getWrappeddShareStorage() private pure returns (WrappeddShareStorage storage $) {
        assembly {
            $.slot := WrappeddShareStorageLocation
        }
    }

    /// ------------------- Initialization ------------------- ///

    function initialize(dShare dShare_, string memory name_, string memory symbol_) public initializer {
        __Ownable_init_unchained(msg.sender);
        __ReentrancyGuard_init_unchained();

        WrappeddShareStorage storage $ = _getWrappeddShareStorage();
        $._underlyingDShare = dShare_;
        $._name = name_;
        $._symbol = symbol_;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// ------------------- Getters ------------------- ///

    /// @inheritdoc IWrappeddShare
    function isLocked() external view returns (bool) {
        WrappeddShareStorage storage $ = _getWrappeddShareStorage();
        return $._isLocked;
    }

    /**
     * @dev Returns the name of the WrappeddShare token.
     * @return A string representing the name.
     */
    function name() public view override returns (string memory) {
        WrappeddShareStorage storage $ = _getWrappeddShareStorage();
        return $._name;
    }

    /**
     * @dev Returns the symbol of the WrappeddShare token.
     * @return A string representing the symbol.
     */
    function symbol() public view override returns (string memory) {
        WrappeddShareStorage storage $ = _getWrappeddShareStorage();
        return $._symbol;
    }

    /**
     * @dev Returns the address of the underlying asset.
     * @return The address of the underlying dShare token.
     */
    function asset() public view override returns (address) {
        WrappeddShareStorage storage $ = _getWrappeddShareStorage();
        return address($._underlyingDShare);
    }

    /// ------------------- Locking Mechanism Lifecycle ------------------- ///

    /// @inheritdoc IWrappeddShare
    function lock() public onlyOwner {
        WrappeddShareStorage storage $ = _getWrappeddShareStorage();
        $._isLocked = true;
        emit VaultLocked();
    }

    /// @inheritdoc IWrappeddShare
    function unlock() public onlyOwner {
        WrappeddShareStorage storage $ = _getWrappeddShareStorage();
        $._isLocked = false;
        emit VaultUnlocked();
    }

    /// ------------------- Vault Operations Lifecycle ------------------- ///

    /// @dev For deposits and mints.
    ///
    /// Emits a {Deposit} event.
    function _deposit(address by, address to, uint256 assets, uint256 shares) internal override {
        // Revert the transaction if deposits are currently locked.
        WrappeddShareStorage storage $ = _getWrappeddShareStorage();
        if ($._isLocked) revert IssuancePaused();

        super._deposit(by, to, assets, shares);
    }

    /// @dev For withdrawals and redemptions.
    ///
    /// Emits a {Withdraw} event.
    function _withdraw(address by, address to, address owner, uint256 assets, uint256 shares) internal override {
        // Revert the transaction if deposits are currently locked.
        WrappeddShareStorage storage $ = _getWrappeddShareStorage();
        if ($._isLocked) revert IssuancePaused();

        super._withdraw(by, to, owner, assets, shares);
    }

    /// ------------------- Transfer Restrictions ------------------- ///

    /**
     * @dev Hook that is called before any token transfer. This includes minting and burning.
     * @param from Address of the sender.
     * @param to Address of the receiver.
     */
    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        // Apply underlying transfer restrictions to this vault token.
        WrappeddShareStorage storage $ = _getWrappeddShareStorage();
        ITransferRestrictor restrictor = $._underlyingDShare.transferRestrictor();
        if (address(restrictor) != address(0)) {
            restrictor.requireNotRestricted(from, to);
        }
    }

    /// @inheritdoc IWrappeddShare
    function isBlacklisted(address account) external view returns (bool) {
        WrappeddShareStorage storage $ = _getWrappeddShareStorage();
        ITransferRestrictor restrictor = $._underlyingDShare.transferRestrictor();
        if (address(restrictor) == address(0)) return false;
        return restrictor.isBlacklisted(account);
    }
}
