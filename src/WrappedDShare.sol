// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {DShare} from "./DShare.sol";
import {ITransferRestrictor} from "./ITransferRestrictor.sol";
import {ERC4626, SafeTransferLib} from "solady/src/tokens/ERC4626.sol";
import {ControlledUpgradeable} from "./deployment/ControlledUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title WrappedDShare Contract
 * @dev An ERC4626 vault wrapper around the rebasing dShare token.
 *      It accumulates the value of rebases and yield distributions.
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/WrappedDShare.sol)
 */
// slither-disable-next-line missing-inheritance
contract WrappedDShare is ControlledUpgradeable, ERC4626, ReentrancyGuardUpgradeable {
    /// ------------------- Types ------------------- ///

    using SafeERC20 for IERC20;

    event NameSet(string name);
    event SymbolSet(string symbol);
    event Recovered(address indexed account, uint256 amount);

    /// ------------------- State ------------------- ///

    struct WrappedDShareStorage {
        DShare _underlyingDShare;
        string _name;
        string _symbol;
    }

    // keccak256(abi.encode(uint256(keccak256("dinaricrypto.storage.WrappeddShare")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WrappedDShareStorageLocation =
        0x152e99b50b5f6a0e49f31b9c18139e0eb82d89de09b8e6a3d245658cb9305300;

    function _getWrappedDShareStorage() private pure returns (WrappedDShareStorage storage $) {
        assembly {
            $.slot := WrappedDShareStorageLocation
        }
    }

    /// ------------------- Version ------------------- ///
    function version() public view override returns (uint8) {
        return 1;
    }

    function publicVersion() public view override returns (string memory) {
        return "1.0.0";
    }

    /// ------------------- Initialization ------------------- ///

    function initialize(address owner, DShare dShare_, string memory name_, string memory symbol_)
        public
        reinitializer(version())
    {
        __AccessControlDefaultAdminRules_init_unchained(0, owner);
        __ReentrancyGuard_init_unchained();

        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        $._underlyingDShare = dShare_;
        $._name = name_;
        $._symbol = symbol_;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// ------------------- Administration ------------------- ///

    /**
     * @dev Sets the name of the WrappedDShare token.
     * @param name_ The new name.
     */
    function setName(string memory name_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        $._name = name_;
        emit NameSet(name_);
    }

    /**
     * @dev Sets the symbol of the WrappedDShare token.
     * @param symbol_ The new symbol.
     */
    function setSymbol(string memory symbol_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        $._symbol = symbol_;
        emit SymbolSet(symbol_);
    }

    /// ------------------- External ------------------- ///
    /**
     * @dev recover assets from the contract.
     * @param account The address to send the token
     * @param amount The amount of dShare tokens send
     */
    function recover(address account, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        emit Recovered(account, amount);
        IERC20(address($._underlyingDShare)).safeTransfer(account, amount);
    }

    /// ------------------- Getters ------------------- ///
    /**
     * @dev Returns the name of the WrappedDShare token.
     * @return A string representing the name.
     */
    function name() public view override returns (string memory) {
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        return $._name;
    }

    /**
     * @dev Returns the symbol of the WrappedDShare token.
     * @return A string representing the symbol.
     */
    function symbol() public view override returns (string memory) {
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        return $._symbol;
    }

    /**
     * @dev Returns the address of the underlying asset.
     * @return The address of the underlying dShare token.
     */
    function asset() public view override returns (address) {
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
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
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        ITransferRestrictor restrictor = $._underlyingDShare.transferRestrictor();
        if (address(restrictor) != address(0)) {
            restrictor.requireNotRestricted(from, to);
        }
    }

    function isBlacklisted(address account) external view returns (bool) {
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        ITransferRestrictor restrictor = $._underlyingDShare.transferRestrictor();
        if (address(restrictor) == address(0)) return false;
        return restrictor.isBlacklisted(account);
    }
}
