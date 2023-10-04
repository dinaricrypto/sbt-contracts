// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {dShare} from "./dShare.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC4626} from "solady/src/tokens/ERC4626.sol";
import {ITransferRestrictor} from "./ITransferRestrictor.sol";
import {IxdShare} from "./IxdShare.sol";
import {TokenManager} from "./TokenManager.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title xdShare Contract
 * @dev This contract acts as a wrapper over the dShare token, providing additional functionalities.
 *         It serves as a reinvestment token that uses dShare as the underlying token.
 *         Additionally, it employs the ERC4626 standard for its operations.
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/xdShare.sol)
 */

// slither-disable-next-line missing-inheritance
contract xdShare is Ownable, ERC4626, IxdShare {
    using SafeERC20 for IERC20;

    /// @notice Reference to the underlying dShare contract.
    dShare public underlyingDShare;
    TokenManager public tokenManager;

    bool public isLocked;


    error DepositsPaused();
    error WithdrawalsPaused();

    event VaultLocked();
    event VaultUnlocked();

    /**
     * @dev Initializes a new instance of the xdShare contract.
     * @param _dShare The address of the underlying dShare token.
     */
    constructor(dShare _dShare, TokenManager _tokenManager) {
        underlyingDShare = _dShare;
        tokenManager = _tokenManager;
    }

    /**
     * @dev Returns the name of the xdShare token.
     * @return A string representing the name.
     */
    function name() public view virtual override returns (string memory) {
        return string(abi.encodePacked("Reinvesting ", underlyingDShare.symbol()));
    }

    /**
     * @dev Returns the symbol of the xdShare token.
     * @return A string representing the symbol.
     */
    function symbol() public view virtual override returns (string memory) {
        return string(abi.encodePacked(underlyingDShare.symbol(), ".x"));
    }

    /**
     * @dev Returns the address of the underlying asset.
     * @return The address of the underlying dShare token.
     */
    function asset() public view virtual override returns (address) {
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
    function _convertVaultBalance() internal {
        underlyingDShare.approve(address(tokenManager), underlyingDShare.balanceOf(address(this)));
        (dShare newUnderlyingDShare,) =
            tokenManager.convert(underlyingDShare, underlyingDShare.balanceOf(address(this)));
        // update underlyDshare
        underlyingDShare = newUnderlyingDShare;
    }

    /// ------------------- Vault Operations Lifecycle ------------------- ///

    /// @dev For deposits and mints.
    ///
    /// Emits a {Deposit} event.
    function _deposit(address by, address to, uint256 assets, uint256 shares) internal virtual override {
        // Revert the transaction if deposits are currently locked.
        if (isLocked) revert DepositsPaused();

        // Check if the underlying token is the current token.
        // If not true, this means a token split has occurred and conversion logic needs to be applied.
        if (!tokenManager.isCurrentToken(address(underlyingDShare))) {
            // transfer assets to vault
            IERC20(address(underlyingDShare)).safeTransferFrom(by, address(this), assets);
            // approve token manager to spend dShare
            underlyingDShare.approve(address(tokenManager), assets);
            // convert dShare to current one
            (, uint256 currentAssets) = tokenManager.convert(underlyingDShare, assets);
            shares = previewDeposit(currentAssets);
            // mint
            super._mint(by, shares);
            // convert vault and update new dShare
            _convertVaultBalance();
        } else {
            // If the token is current (no splits), call the parent _deposit function with the original assets and shares.
            // This is the standard deposit logic without any conversion necessary.
            super._deposit(by, to, assets, shares);
        }
    }

    /// @dev For withdrawals and redemptions.
    ///
    /// Emits a {Withdraw} event.
    function _withdraw(address by, address to, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        if (isLocked) revert WithdrawalsPaused();
        if (!tokenManager.isCurrentToken(address(underlyingDShare))) {
            super._withdraw(by, to, owner, assets, shares);
        } else {
            super._withdraw(by, to, owner, assets, shares);
        }
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting and burning.
     * @param from Address of the sender.
     * @param to Address of the receiver.
     */
    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        ITransferRestrictor restrictor = underlyingDShare.transferRestrictor();

        if (address(restrictor) != address(0)) {
            restrictor.requireNotRestricted(from, to);
        }
    }

    /// ------------------- Transfer Restrictions Lifecycle ------------------- ///

    /// @inheritdoc IxdShare
    function isBlacklisted(address account) external view returns (bool) {
        ITransferRestrictor restrictor = underlyingDShare.transferRestrictor();
        if (address(restrictor) == address(0)) return false;
        return restrictor.isBlacklisted(account);
    }
}
