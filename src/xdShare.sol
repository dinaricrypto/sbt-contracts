// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {dShare} from "./dShare.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC4626} from "solady/src/tokens/ERC4626.sol";
import {ITransferRestrictor} from "./ITransferRestrictor.sol";
import {IxdShare} from "./IxdShare.sol";

/**
 * @title xdShare Contract
 * @dev This contract acts as a wrapper over the dShare token, providing additional functionalities.
 *         It serves as a reinvestment token that uses dShare as the underlying token.
 *         Additionally, it employs the ERC4626 standard for its operations.
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/xdShare.sol)
 */

// slither-disable-next-line missing-inheritance
contract xdShare is Ownable, ERC4626, IxdShare {
    /// @notice Reference to the underlying dShare contract.
    dShare public immutable underlyingDShare;

    bool public isLocked;

    error DepositsPaused();
    error WithdrawalsPaused();

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

    /// ------------------- Vault Operations Lifecycle ------------------- ///

    /// @dev For deposits and mints.
    ///
    /// Emits a {Deposit} event.
    function _deposit(address by, address to, uint256 assets, uint256 shares) internal virtual override {
        if (isLocked) revert DepositsPaused();
        super._deposit(by, to, assets, shares);
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
        super._withdraw(by, to, owner, assets, shares);
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
