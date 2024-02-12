// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {ERC4626, SafeTransferLib} from "solady/src/tokens/ERC4626.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableMap} from "openzeppelin-contracts/contracts/utils/structs/EnumerableMap.sol";
import {DShare} from "./DShare.sol";
import {ITransferRestrictor} from "./ITransferRestrictor.sol";
import {EnumerableMapMath} from "./common/EnumerableMapMath.sol";
import {IWrappedDShare} from "./IWrappedDShare.sol";

/**
 * @title WrappedDShare Contract
 * @dev An ERC4626 vault wrapper around the rebasing dShare token.
 *      It accumulates the value of rebases and yield distributions.
 * @author Modified from solady (solady/src/tokens/ERC4626.sol)
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/WrappedDShare.sol)
 */
// slither-disable-next-line missing-inheritance
contract WrappedDShare is IWrappedDShare, Initializable, ERC4626, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /// ------------------- Types ------------------- ///

    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableMapMath for EnumerableMap.AddressToUintMap;

    event NameSet(string name);
    event SymbolSet(string symbol);
    // TODO: events for lockFutureDividend and integrateRates

    error ActiveDividend();

    /// ------------------- State ------------------- ///

    struct WrappedDShareStorage {
        DShare _underlyingDShare;
        string _name;
        string _symbol;
        uint256 _premiumRateTotalAssets;
        uint256 _dividendIndex;
        // per account active premium amounts per dividend index
        mapping(uint256 => EnumerableMap.AddressToUintMap) _premiumShares;
    }

    // keccak256(abi.encode(uint256(keccak256("dinaricrypto.storage.WrappeddShare")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WrappedDShareStorageLocation =
        0x152e99b50b5f6a0e49f31b9c18139e0eb82d89de09b8e6a3d245658cb9305300;

    function _getWrappedDShareStorage() private pure returns (WrappedDShareStorage storage $) {
        assembly {
            $.slot := WrappedDShareStorageLocation
        }
    }

    /// ------------------- Initialization ------------------- ///

    function initialize(address owner, DShare dShare_, string memory name_, string memory symbol_) public initializer {
        __Ownable_init_unchained(owner);
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
    function setName(string memory name_) external onlyOwner {
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        $._name = name_;
        emit NameSet(name_);
    }

    /**
     * @dev Sets the symbol of the WrappedDShare token.
     * @param symbol_ The new symbol.
     */
    function setSymbol(string memory symbol_) external onlyOwner {
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        $._symbol = symbol_;
        emit SymbolSet(symbol_);
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

    /// ------------------- Ex-Dividend Premium ERC4626 ------------------- ///

    function lockFutureDividend(uint256 amount) external {
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        if ($._premiumRateTotalAssets > 0) revert ActiveDividend();

        $._premiumRateTotalAssets = totalAssets() + amount;
    }

    function integrateRates() external {
        _checkResetPremiumRate();
    }

    // TODO: apply reset for deposits and withdrawals
    function _checkResetPremiumRate() internal {
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        // if total assets have surpassed the premium rate total assets, consolidate rates by clearing the premium amount
        uint256 premiumTotalAssets = $._premiumRateTotalAssets;
        if (premiumTotalAssets > 0 && totalAssets() >= premiumTotalAssets) {
            $._premiumRateTotalAssets = 0;
            $._dividendIndex++;
        }
    }

    function convertToSharesPremium(uint256 premiumTotalAssets, uint256 assets)
        public
        view
        virtual
        returns (uint256 shares)
    {
        uint256 o = _decimalsOffset();
        if (o == 0) {
            return FixedPointMathLib.fullMulDiv(assets, totalSupply() + 1, _inc_(premiumTotalAssets));
        }
        return FixedPointMathLib.fullMulDiv(assets, totalSupply() + 10 ** o, _inc_(premiumTotalAssets));
    }

    function convertToAssetsPremium(uint256 premiumTotalAssets, uint256 shares)
        public
        view
        virtual
        returns (uint256 assets)
    {
        uint256 o = _decimalsOffset();
        if (o == 0) {
            return FixedPointMathLib.fullMulDiv(shares, premiumTotalAssets + 1, _inc_(totalSupply()));
        }
        return FixedPointMathLib.fullMulDiv(shares, premiumTotalAssets + 1, totalSupply() + 10 ** o);
    }

    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
        // new shares are all premium if there is an active dividend
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        uint256 premiumTotalAssets = $._premiumRateTotalAssets;
        if (premiumTotalAssets > 0) {
            shares = convertToSharesPremium(premiumTotalAssets, assets);
        } else {
            shares = convertToShares(assets);
        }
    }

    function previewMint(uint256 shares) public view override returns (uint256 assets) {
        // new shares are all premium if there is an active dividend
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        uint256 premiumTotalAssets = $._premiumRateTotalAssets;
        if (premiumTotalAssets > 0) {
            uint256 o = _decimalsOffset();
            if (o == 0) {
                return FixedPointMathLib.fullMulDivUp(shares, premiumTotalAssets + 1, _inc_(totalSupply()));
            }
            return FixedPointMathLib.fullMulDivUp(shares, premiumTotalAssets + 1, totalSupply() + 10 ** o);
        } else {
            return super.previewMint(shares);
        }
    }

    function previewWithdraw(address account, uint256 assets) public view virtual returns (uint256 shares) {
        // an account may have both premium and non-premium shares
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        uint256 premiumTotalAssets = $._premiumRateTotalAssets;
        if (premiumTotalAssets > 0) {
            uint256 premiumShares = $._premiumShares[$._dividendIndex].get(account);
            uint256 o = _decimalsOffset();
            if (o == 0) {
                shares = FixedPointMathLib.fullMulDivUp(assets, premiumTotalAssets + 1, _inc_(totalAssets()));
            } else {
                shares = FixedPointMathLib.fullMulDivUp(assets, premiumTotalAssets + 10 ** o, _inc_(totalAssets()));
            }
            if (shares > premiumShares) {
                // TODO: use correct rounding vs convertToAssetsPremium?
                shares = premiumShares
                    + super.previewWithdraw(assets - convertToAssetsPremium(premiumTotalAssets, premiumShares));
            }
        } else {
            shares = super.previewWithdraw(assets);
        }
    }

    function previewRedeem(address account, uint256 shares) public view virtual returns (uint256 assets) {
        // an account may have both premium and non-premium shares
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        uint256 premiumTotalAssets = $._premiumRateTotalAssets;
        if ($._premiumRateTotalAssets > 0) {
            // redeem premium shares first
            uint256 premiumShares = $._premiumShares[$._dividendIndex].get(account);
            if (premiumShares > 0) {
                if (shares <= premiumShares) {
                    return convertToAssetsPremium(premiumTotalAssets, shares);
                }
                assets =
                    convertToAssetsPremium(premiumTotalAssets, premiumShares) + convertToAssets(shares - premiumShares);
            } else {
                assets = convertToAssets(shares);
            }
        } else {
            assets = convertToAssets(shares);
        }
    }

    // TODO: implement maxWithdraw
    // function maxWithdraw(address owner) public view virtual returns (uint256 maxAssets) {
    //     WrappedDShareStorage storage $ = _getWrappedDShareStorage();
    //     uint256 premiumTotalAssets = $._premiumRateTotalAssets;
    //     if (premiumTotalAssets > 0) {
    //         maxAssets = convertToAssetsPremium(premiumTotalAssets, balanceOf(owner));
    //     } else {
    //         maxAssets = convertToAssets(balanceOf(owner));
    //     }
    // }

    function deposit(uint256 assets, address to) public override returns (uint256 shares) {
        if (assets > maxDeposit(to)) _revert_(0xb3c61a83); // `DepositMoreThanMax()`.
        // new shares are all premium if there is an active dividend
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        uint256 premiumTotalAssets = $._premiumRateTotalAssets;
        if (premiumTotalAssets > 0) {
            shares = convertToSharesPremium(premiumTotalAssets, assets);
            $._premiumShares[$._dividendIndex].increment(msg.sender, shares);
        } else {
            shares = convertToShares(assets);
        }
        _deposit(msg.sender, to, assets, shares);
    }

    function mint(uint256 shares, address to) public override returns (uint256 assets) {
        if (shares > maxMint(to)) _revert_(0x6a695959); // `MintMoreThanMax()`.
        // new shares are all premium if there is an active dividend
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        uint256 premiumTotalAssets = $._premiumRateTotalAssets;
        if (premiumTotalAssets > 0) {
            uint256 o = _decimalsOffset();
            if (o == 0) {
                assets = FixedPointMathLib.fullMulDivUp(shares, premiumTotalAssets + 1, _inc_(totalSupply()));
            } else {
                assets = FixedPointMathLib.fullMulDivUp(shares, premiumTotalAssets + 1, totalSupply() + 10 ** o);
            }
            $._premiumShares[$._dividendIndex].increment(msg.sender, shares);
        } else {
            assets = super.previewMint(shares);
        }
        _deposit(msg.sender, to, assets, shares);
    }

    function withdraw(uint256 assets, address to, address owner) public override returns (uint256 shares) {
        if (assets > maxWithdraw(owner)) _revert_(0x936941fc); // `WithdrawMoreThanMax()`.
        // an account may have both premium and non-premium shares
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        uint256 premiumTotalAssets = $._premiumRateTotalAssets;
        if (premiumTotalAssets > 0) {
            EnumerableMap.AddressToUintMap storage premiumShareMap = $._premiumShares[$._dividendIndex];
            if (premiumShareMap.contains(msg.sender)) {
                uint256 o = _decimalsOffset();
                if (o == 0) {
                    shares = FixedPointMathLib.fullMulDivUp(assets, premiumTotalAssets + 1, _inc_(totalAssets()));
                } else {
                    shares = FixedPointMathLib.fullMulDivUp(assets, premiumTotalAssets + 10 ** o, _inc_(totalAssets()));
                }
                // redeem premium shares first
                uint256 premiumShares = premiumShareMap.get(msg.sender);
                if (shares > premiumShares) {
                    // TODO: use correct rounding vs convertToAssetsPremium?
                    shares = premiumShares
                        + super.previewWithdraw(assets - convertToAssetsPremium(premiumTotalAssets, premiumShares));
                    premiumShareMap.remove(msg.sender);
                } else if (shares == premiumShares) {
                    premiumShareMap.remove(msg.sender);
                } else {
                    premiumShareMap.set(msg.sender, premiumShares - shares);
                }
            } else {
                shares = super.previewWithdraw(assets);
            }
        } else {
            shares = super.previewWithdraw(assets);
        }
        _withdraw(msg.sender, to, owner, assets, shares);
    }

    function redeem(uint256 shares, address to, address owner) public override returns (uint256 assets) {
        if (shares > maxRedeem(owner)) _revert_(0x4656425a); // `RedeemMoreThanMax()`.
        WrappedDShareStorage storage $ = _getWrappedDShareStorage();
        uint256 premiumTotalAssets = $._premiumRateTotalAssets;
        if ($._premiumRateTotalAssets > 0) {
            // an account may have both premium and non-premium shares
            EnumerableMap.AddressToUintMap storage premiumShareMap = $._premiumShares[$._dividendIndex];
            if (premiumShareMap.contains(msg.sender)) {
                // redeem premium shares first
                uint256 premiumShares = premiumShareMap.get(msg.sender);
                if (shares <= premiumShares) {
                    assets = convertToAssetsPremium(premiumTotalAssets, shares);
                    premiumShareMap.set(msg.sender, premiumShares - shares);
                } else {
                    assets = convertToAssetsPremium(premiumTotalAssets, premiumShares)
                        + convertToAssets(shares - premiumShares);
                    premiumShareMap.remove(msg.sender);
                }
            } else {
                assets = convertToAssets(shares);
            }
        } else {
            assets = convertToAssets(shares);
        }
        _withdraw(msg.sender, to, owner, assets, shares);
    }

    /// @dev Private helper to return the value plus one.
    function _inc_(uint256 x) private pure returns (uint256) {
        unchecked {
            return x + 1;
        }
    }

    /// @dev Internal helper for reverting efficiently.
    function _revert_(uint256 s) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, s)
            revert(0x1c, 0x04)
        }
    }
}
