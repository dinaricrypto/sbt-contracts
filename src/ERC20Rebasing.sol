// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {NumberUtils} from "./common/NumberUtils.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

/// @notice Rebasing ERC20 token as an in-place upgrade to solady erc20
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/dShare.sol)
abstract contract ERC20Rebasing is ERC20 {
    uint256 private constant _TRANSFER_EVENT_SIGNATURE =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    uint256 private constant _TOTAL_SUPPLY_SLOT = 0x05345cdf77eb68f44c;
    uint256 private constant _BALANCE_SLOT_SEED = 0x87a211a2;

    uint128 internal constant _INITIAL_BALANCE_PER_SHARE = 1 ether;

    /**
     * @dev Returns the number of tokens an internal share amount represents.
     * This amount is assumed to have 18 decimals and is divided by 10 **18 when applied.
     */
    function balancePerShare() public view virtual returns (uint128);

    function sharesToBalance(uint256 shares) public view returns (uint256) {
        return FixedPointMathLib.fullMulDiv(shares, balancePerShare(), _INITIAL_BALANCE_PER_SHARE); // floor
    }

    function balanceToShares(uint256 balance) public view returns (uint256) {
        return FixedPointMathLib.fullMulDiv(balance, _INITIAL_BALANCE_PER_SHARE, balancePerShare()); // floor
    }

    /// ------------------ ERC20 ------------------

    function totalSupply() public view virtual override returns (uint256) {
        return sharesToBalance(super.totalSupply());
    }

    /// @notice Returns the maximum supply of the token in balance.
    /// @dev Useful for sanity checks before minting since the total supply of shares can overflow.
    function maxSupply() public view virtual returns (uint256) {
        // Reduced maxSupply of shares to prevent overflow in balanceToShares and other functions
        uint128 balancePerShare_ = balancePerShare();
        if (balancePerShare_ < _INITIAL_BALANCE_PER_SHARE) {
            // maxSupply = type(uint256).max * balancePerShare_ / _INITIAL_BALANCE_PER_SHARE
            return FixedPointMathLib.fullMulDiv(type(uint256).max, balancePerShare_, _INITIAL_BALANCE_PER_SHARE);
        } else if (balancePerShare_ > _INITIAL_BALANCE_PER_SHARE) {
            // maxSupply = type(uint256).max * _INITIAL_BALANCE_PER_SHARE / balancePerShare_
            return FixedPointMathLib.fullMulDiv(type(uint256).max, _INITIAL_BALANCE_PER_SHARE, balancePerShare_);
        }
        return type(uint256).max;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return sharesToBalance(super.balanceOf(account));
    }

    function sharesOf(address account) public view virtual returns (uint256) {
        return super.balanceOf(account);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    // Convert to shares
    function _transfer(address from, address to, uint256 amount) internal virtual override {
        _beforeTokenTransfer(from, to, amount);
        uint256 shares = balanceToShares(amount);
        /// @solidity memory-safe-assembly
        assembly {
            let from_ := shl(96, from)
            // Compute the balance slot and load its value.
            mstore(0x0c, or(from_, _BALANCE_SLOT_SEED))
            let fromBalanceSlot := keccak256(0x0c, 0x20)
            let fromBalance := sload(fromBalanceSlot)
            // Revert if insufficient balance.
            if gt(shares, fromBalance) {
                mstore(0x00, 0xf4d678b8) // `InsufficientBalance()`.
                revert(0x1c, 0x04)
            }
            // Subtract and store the updated balance.
            sstore(fromBalanceSlot, sub(fromBalance, shares))
            // Compute the balance slot of `to`.
            mstore(0x00, to)
            let toBalanceSlot := keccak256(0x0c, 0x20)
            // Add and store the updated balance of `to`.
            // Will not overflow because the sum of all user balances
            // cannot exceed the maximum uint256 value.
            sstore(toBalanceSlot, add(sload(toBalanceSlot), shares))
            // Emit the {Transfer} event.
            mstore(0x20, amount)
            log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, from_), shr(96, mload(0x0c)))
        }
        _afterTokenTransfer(from, to, amount);
    }

    // Convert to shares
    function _mint(address to, uint256 amount) internal virtual override {
        _beforeTokenTransfer(address(0), to, amount);
        uint256 totalSharesBefore = super.totalSupply();
        // Floor the shares to mint
        uint256 shares = balanceToShares(amount);
        // Check the total supply limit for shares
        uint256 totalSharesAfter = 0;
        unchecked {
            totalSharesAfter = totalSharesBefore + shares;
        }
        // Check overflow
        if (totalSharesAfter < totalSharesBefore) revert TotalSupplyOverflow();
        // Check total supply limit, can also revert with FullMulDivFailed in fullMulDivUp
        // Round up for total supply limit check
        if (
            FixedPointMathLib.fullMulDivUp(totalSharesAfter, balancePerShare(), _INITIAL_BALANCE_PER_SHARE)
                > maxSupply()
        ) revert TotalSupplyOverflow();
        /// @solidity memory-safe-assembly
        assembly {
            // Store the updated total supply.
            sstore(_TOTAL_SUPPLY_SLOT, totalSharesAfter)
            // Compute the balance slot and load its value.
            mstore(0x0c, _BALANCE_SLOT_SEED)
            mstore(0x00, to)
            let toBalanceSlot := keccak256(0x0c, 0x20)
            // Add and store the updated balance.
            sstore(toBalanceSlot, add(sload(toBalanceSlot), shares))
            // Emit the {Transfer} event.
            mstore(0x20, amount)
            log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, 0, shr(96, mload(0x0c)))
        }
        _afterTokenTransfer(address(0), to, amount);
    }

    // Convert to shares
    function _burn(address from, uint256 amount) internal virtual override {
        _beforeTokenTransfer(from, address(0), amount);
        // Round up the shares to burn in favor of the contract
        uint256 shares = FixedPointMathLib.fullMulDivUp(amount, _INITIAL_BALANCE_PER_SHARE, balancePerShare());
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the balance slot and load its value.
            mstore(0x0c, _BALANCE_SLOT_SEED)
            mstore(0x00, from)
            let fromBalanceSlot := keccak256(0x0c, 0x20)
            let fromBalance := sload(fromBalanceSlot)
            // Revert if insufficient balance.
            if gt(shares, fromBalance) {
                mstore(0x00, 0xf4d678b8) // `InsufficientBalance()`.
                revert(0x1c, 0x04)
            }
            // Subtract and store the updated balance.
            sstore(fromBalanceSlot, sub(fromBalance, shares))
            // Subtract and store the updated total supply.
            sstore(_TOTAL_SUPPLY_SLOT, sub(sload(_TOTAL_SUPPLY_SLOT), shares))
            // Emit the {Transfer} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, shl(96, from)), 0)
        }
        _afterTokenTransfer(from, address(0), amount);
    }
}
