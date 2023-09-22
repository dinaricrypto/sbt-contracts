// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {dShare} from "./dShare.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "openzeppelin-contracts/contracts/security/Pausable.sol";
import {ERC4626} from "solady/src/tokens/ERC4626.sol";
import {ITransferRestrictor} from "./ITransferRestrictor.sol";

/**
 * @title xdShare Contract
 * @dev This contract acts as a wrapper over the dShare token, providing additional functionalities.
 *         It serves as a reinvestment token that uses dShare as the underlying token.
 *         Additionally, it employs the ERC4626 standard for its operations.
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/xdShare.sol)
 */

// slither-disable-next-line missing-inheritance
contract xdShare is Ownable, ERC4626, Pausable {
    /// @notice Reference to the underlying dShare contract.
    dShare public immutable underlyingDShare;

    bool isLocked;

    error DepositPaused();
    error WithdrawalPaused();

    event VaultLocked();
    event VaultUnlocked();

    /**
     * @dev Initializes a new instance of the xdShare contract.
     * @param _dShare The address of the underlying dShare token.
     */
    constructor(dShare _dShare) {
        underlyingDShare = _dShare;
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

    /**
     * @dev Locks the contract to prevent deposit and withdrawal operations.
     * Can only be called by the owner of the contract.
     */
    function lock() public onlyOwner {
        isLocked = true;
        emit VaultLocked();
    }

    /**
     * @dev Unlocks the contract to allow deposit and withdrawal operations.
     * Can only be called by the owner of the contract.
     */
    function unlock() public onlyOwner {
        isLocked = false;
        emit VaultUnlocked();
    }

    /**
     * @dev Allows a user to deposit assets into the contract.
     * Reverts if the contract is locked.
     * @param assets The amount of assets to deposit.
     * @param to The address to credit the deposit to.
     * @return shares The amount of shares received in exchange for the deposit.
     */
    function deposit(uint256 assets, address to) public virtual override returns (uint256 shares) {
        if (isLocked) revert DepositPaused();
        shares = super.deposit(assets, to);
    }

    /**
     * @dev Allows a user to withdraw assets from the contract.
     * Reverts if the contract is locked.
     * @param assets The amount of assets to withdraw.
     * @param to The address to send the withdrawn assets to.
     * @param owner The owner address for this withdrawal operation. Typically used for permissions or validation.
     * @return shares The amount of shares that will be burned in exchange for the withdrawal.
     */
    function withdraw(uint256 assets, address to, address owner) public virtual override returns (uint256 shares) {
        if (isLocked) revert WithdrawalPaused();
        shares = super.withdraw(assets, to, owner);
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
     * @dev Checks if an account is blacklisted in the underlying dShare contract.
     * @param account Address of the account to check.
     * @return True if the account is blacklisted, false otherwise.
     */
    function isBlacklisted(address account) external view returns (bool) {
        ITransferRestrictor restrictor = underlyingDShare.transferRestrictor();
        if (address(restrictor) == address(0)) return false;
        return restrictor.isBlacklisted(account);
    }
}
