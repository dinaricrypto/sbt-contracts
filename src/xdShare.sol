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

    uint8 public totalMutiple = 1;
    uint8 public migrationCount;

    bool public isLocked;

    mapping(address => uint8) private userMigrationCount;
    mapping(address => mapping(uint8 => bool)) private userHasMigrated;

    error DepositsPaused();
    error MigrationLocked();
    error WithdrawalsPaused();
    error MigrationAlreadyDone();
    error UserLostMigrationRight();

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
        _lock();
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
            // lock the vault
            _lock();
            // update migration count
            migrationCount += 1;
            userMigrationCount[to] += 1;
            userHasMigrated[to][migrationCount] = true;
            // migrate OldDShare to NewDShare
            _migrateOldShareToNewShare();
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

    /**
     * @dev Migrate old shares to new shares based on the current split.
     * Users can migrate only when their migration count matches the global migration count,
     * and they haven't migrated for the current count before.
     */
    function migrateOldShareToNewShare() public returns (uint256 newShares) {
        // Check if the user has the right to migrate at the current migration count
        if (userMigrationCount[msg.sender] + 1 < migrationCount) revert UserLostMigrationRight();

        // Check if the user has already migrated for the current count
        if (userHasMigrated[msg.sender][migrationCount]) revert MigrationAlreadyDone();

        // Mark that the user has migrated for the current count
        userHasMigrated[msg.sender][migrationCount] = true;

        // Increment the user's migration count
        userMigrationCount[msg.sender] += 1;

        // Perform the actual migration
        newShares = _migrateOldShareToNewShare();
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
        if (!tokenManager.isCurrentToken(address(underlyingDShare))) {} else {
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

    /**
     * @dev Migrate old shares to new shares based on token splits.
     * @return newShares The adjusted amount of new shares.
     */
    function _migrateOldShareToNewShare() internal returns (uint256 newShares) {
        // Get split information from the TokenManager
        (, uint8 multiple, bool reverse) = tokenManager.splits(underlyingDShare);

        // Get the balance of the user
        uint256 userBalance = balanceOf(msg.sender);
        // Calculate newShares based on splits
        if (reverse) {
            if (multiple > userBalance) {
                // Handle the case where multiple is greater than or equal to userBalance
                newShares = userBalance;
                _burn(msg.sender, newShares);
            } else {
                uint256 amountToAdjust = userBalance / multiple;
                newShares = userBalance - amountToAdjust;
                _burn(msg.sender, newShares);
            }
        } else {
            uint256 amountToAdjust = userBalance * multiple;
            newShares = amountToAdjust - userBalance;
            _mint(msg.sender, newShares);
        }
        // Return the adjusted amount of new shares
        return newShares;
    }

    function _lock() internal {
        isLocked = true;
    }

    /// ------------------- Transfer Restrictions Lifecycle ------------------- ///

    /// @inheritdoc IxdShare
    function isBlacklisted(address account) external view returns (bool) {
        ITransferRestrictor restrictor = underlyingDShare.transferRestrictor();
        if (address(restrictor) == address(0)) return false;
        return restrictor.isBlacklisted(account);
    }
}
