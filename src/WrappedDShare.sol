// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {DShare} from "./DShare.sol";
import {ITransferRestrictor} from "./ITransferRestrictor.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC4626, SafeTransferLib} from "solady/src/tokens/ERC4626.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
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
contract WrappedDShare is Initializable, ERC4626, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    event NameSet(string name);
    event SymbolSet(string symbol);

    struct WrappedDShareStorage {
        DShare _underlyingDShare;
        string _name;
        string _symbol;
    }

    bytes32 private constant WrappedDShareStorageLocation =
        0x152e99b50b5f6a0e49f31b9c18139e0eb82d89de09b8e6a3d245658cb9305300;

    function _getWrappedDShareStorage() private pure returns (WrappedDShareStorage storage $) {
        assembly {
            $.slot := WrappedDShareStorageLocation
        }
    }

    function initialize(address owner, DShare dShare_, string memory name_, string memory symbol_) public initializer {
        __Ownable_init_unchained(owner);
        __ReentrancyGuard_init_unchained();

        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        $._underlyingDShare = dShare_;
        $._name = name_;
        $._symbol = symbol_;
    }

    constructor() {
        _disableInitializers();
    }

    function setName(string memory name_) external onlyOwner {
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        $._name = name_;
        emit NameSet(name_);
    }

    function setSymbol(string memory symbol_) external onlyOwner {
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        $._symbol = symbol_;
        emit SymbolSet(symbol_);
    }

    function name() public view override returns (string memory) {
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        return $._name;
    }

    function symbol() public view override returns (string memory) {
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        return $._symbol;
    }

    function asset() public view override returns (address) {
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        return address($._underlyingDShare);
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
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

    // Override to scale shares by decimals
    function convertToShares(uint256 assets) public view virtual override returns (uint256 shares) {
        uint256 assetDecimals = _underlyingDecimals(); // 18
        uint256 vaultDecimals = decimals(); // Will be 18 after override
        // Scale assets to match share decimals
        uint256 scaledAssets = assets * (10 ** vaultDecimals) / (10 ** assetDecimals);
        uint256 baseShares = super.convertToShares(scaledAssets);
        shares = baseShares;
    }

    function convertToAssets(uint256 shares) public view virtual override returns (uint256 assets) {
        uint256 assetDecimals = _underlyingDecimals();
        uint256 vaultDecimals = decimals();
        uint256 baseAssets = super.convertToAssets(shares);
        // Scale assets back to asset decimals
        assets = baseAssets * (10 ** assetDecimals) / (10 ** vaultDecimals);
    }

    function previewDeposit(uint256 assets) public view virtual override returns (uint256 shares) {
        shares = convertToShares(assets);
    }

    function previewMint(uint256 shares) public view virtual override returns (uint256 assets) {
        uint256 assetDecimals = _underlyingDecimals();
        uint256 vaultDecimals = decimals();
        uint256 scaledAssets = super.previewMint(shares);
        assets = scaledAssets * (10 ** assetDecimals) / (10 ** vaultDecimals);
    }

    function previewWithdraw(uint256 assets) public view virtual override returns (uint256 shares) {
        uint256 assetDecimals = _underlyingDecimals();
        uint256 vaultDecimals = decimals();
        uint256 scaledAssets = assets * (10 ** vaultDecimals) / (10 ** assetDecimals);
        shares = super.previewWithdraw(scaledAssets);
    }

    function previewRedeem(uint256 shares) public view virtual override returns (uint256 assets) {
        uint256 assetDecimals = _underlyingDecimals();
        uint256 vaultDecimals = decimals();
        uint256 baseAssets = super.previewRedeem(shares);
        assets = baseAssets * (10 ** assetDecimals) / (10 ** vaultDecimals);
    }

    // Ensure vault shares have the same decimals as the underlying asset
    function decimals() public view virtual override returns (uint8) {
        return _underlyingDecimals();
    }
}
