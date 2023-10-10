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

// take index in original dshare and apply split multipliers to get current

contract xdShare is Ownable, ERC4626, IxdShare {
    using SafeERC20 for IERC20;

    /// @notice Reference to the underlying dShare contract.
    dShare public underlyingDShare;
    TokenManager public tokenManager;

    /// @inheritdoc IxdShare
    bool public isLocked;

    error IssuancePaused();
    error SplitConversionNeeded();
    error ConversionCurrent();

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
    function name() public view override returns (string memory) {
        return string(abi.encodePacked("Reinvesting ", underlyingDShare.symbol()));
    }

    /**
     * @dev Returns the symbol of the xdShare token.
     * @return A string representing the symbol.
     */
    function symbol() public view override returns (string memory) {
        return string(abi.encodePacked(underlyingDShare.symbol(), ".x"));
    }

    /**
     * @dev Returns the address of the underlying asset.
     * @return The address of the underlying dShare token.
     */
    function asset() public view override returns (address) {
        return address(underlyingDShare);
    }

    // This offers inflation attack prevention
    // TODO: fix split conversion math and turn on
    function _useVirtualShares() internal pure override returns (bool) {
        return false;
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

    function convertVaultBalance() public {
        if (tokenManager.isCurrentToken(address(underlyingDShare))) revert ConversionCurrent();

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
        if (!tokenManager.isCurrentToken(address(underlyingDShare))) revert SplitConversionNeeded();
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
