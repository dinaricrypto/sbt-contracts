// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {dShare} from "../dShare.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC4626, SafeTransferLib} from "solady/src/tokens/ERC4626.sol";
import {ITransferRestrictor} from "../ITransferRestrictor.sol";
import {IxdShare} from "./IxdShare.sol";
import {IdShareManager} from "../IdShareManager.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

/**
 * @title xdShare Contract
 * @dev This contract acts as a wrapper over the dShare token, providing additional functionalities.
 *      It serves as a reinvestment token that uses dShare as the underlying token.
 *      Additionally, it employs the ERC4626 standard for its operations.
 *      If TokenManager is not used, make sure that dShare will never split.
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/xdShare.sol)
 */
contract xdShare is IxdShare, Ownable, ERC4626, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidTokenManager();
    error IssuancePaused();
    error SplitConversionNeeded();
    error ConversionCurrent();

    event VaultLocked();
    event VaultUnlocked();

    IdShareManager public immutable tokenManager;

    /// @notice Reference to the underlying dShare contract.
    dShare public underlyingDShare;

    /// @inheritdoc IxdShare
    bool public isLocked;

    /// @dev Token name
    string private _name;
    /// @dev Token symbol
    string private _symbol;

    /**
     * @dev Initializes a new instance of the xdShare contract.
     * @param _dShare The address of the underlying dShare token.
     * @param _tokenManager The address of the token manager.
     * @param name_ The name of the xdShare token.
     * @param symbol_ The symbol of the xdShare token.
     */
    constructor(dShare _dShare, IdShareManager _tokenManager, string memory name_, string memory symbol_) {
        // Verify tokenManager setup
        if (address(_tokenManager) != address(0) && !_tokenManager.isCurrentToken(address(_dShare))) {
            revert InvalidTokenManager();
        }

        underlyingDShare = _dShare;
        tokenManager = _tokenManager;
        _name = name_;
        _symbol = symbol_;
    }

    /// ------------------- Getters ------------------- ///

    /**
     * @dev Returns the name of the xdShare token.
     * @return A string representing the name.
     */
    function name() public view override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the xdShare token.
     * @return A string representing the symbol.
     */
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the address of the underlying asset.
     * @return The address of the underlying dShare token.
     */
    function asset() public view override returns (address) {
        return address(underlyingDShare);
    }

    /// ------------------- Locking Mechanism Lifecycle ------------------- ///

    /// @inheritdoc IxdShare
    function lock() public onlyOwner {
        isLocked = true;
        emit VaultLocked();
    }

    /// @inheritdoc IxdShare
    function unlock() public onlyOwner {
        isLocked = false;
        emit VaultUnlocked();
    }

    /// ------------------- Splitting Operations Lifecycle ------------------- ///

    function convertVaultBalance() external onlyOwner nonReentrant {
        if (address(tokenManager) == address(0) || tokenManager.isCurrentToken(address(underlyingDShare))) {
            revert ConversionCurrent();
        }

        SafeTransferLib.safeApprove(
            address(underlyingDShare), address(tokenManager), underlyingDShare.balanceOf(address(this))
        );
        // slither-disable-next-line unused-return
        (dShare newUnderlyingDShare,) =
            tokenManager.convert(underlyingDShare, underlyingDShare.balanceOf(address(this)));
        // update underlyDshare
        // slither-disable-next-line reentrancy-no-eth
        underlyingDShare = newUnderlyingDShare;
    }

    /**
     * @dev Converts the entire balance of the specified token to the current token.
     * @param token The token to convert
     */
    function sweepConvert(dShare token) external nonReentrant onlyOwner {
        _issuancePreCheck();
        uint256 tokenBalance = token.balanceOf(address(this));
        if (tokenBalance > 0) {
            SafeTransferLib.safeApprove(address(token), address(tokenManager), tokenBalance);
            // slither-disable-next-line unused-return
            tokenManager.convert(token, tokenBalance);
        }
    }

    /// ------------------- Vault Operations Lifecycle ------------------- ///

    /// @dev For deposits and mints.
    ///
    /// Emits a {Deposit} event.
    function _deposit(address by, address to, uint256 assets, uint256 shares) internal override {
        _issuancePreCheck();

        super._deposit(by, to, assets, shares);
    }

    /// @dev For withdrawals and redemptions.
    ///
    /// Emits a {Withdraw} event.
    function _withdraw(address by, address to, address owner, uint256 assets, uint256 shares) internal override {
        _issuancePreCheck();

        super._withdraw(by, to, owner, assets, shares);
    }

    function _issuancePreCheck() private view {
        // Revert the transaction if deposits are currently locked.
        if (isLocked) revert IssuancePaused();
        if (address(tokenManager) != address(0) && !tokenManager.isCurrentToken(address(underlyingDShare))) {
            revert SplitConversionNeeded();
        }
    }

    /// ------------------- Transfer Restrictions ------------------- ///

    /**
     * @dev Hook that is called before any token transfer. This includes minting and burning.
     * @param from Address of the sender.
     * @param to Address of the receiver.
     */
    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        // Apply underlying transfer restrictions to this vault token.
        ITransferRestrictor restrictor = underlyingDShare.transferRestrictor();
        if (address(restrictor) != address(0)) {
            restrictor.requireNotRestricted(from, to);
        }
    }

    /// @inheritdoc IxdShare
    function isBlacklisted(address account) external view returns (bool) {
        ITransferRestrictor restrictor = underlyingDShare.transferRestrictor();
        if (address(restrictor) == address(0)) return false;
        return restrictor.isBlacklisted(account);
    }
}
