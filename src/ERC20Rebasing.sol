// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {ERC20} from "solady/src/tokens/ERC20.sol";
// TODO: replace with prbmath for muldiv18
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

// solady erc20 was usied in the initial deployment
// this rebasing erc20 is an extension of solady erc20 which preserves existing balances when upgrading from solady erc20
// TODO: use higher prevision PRB math to reduce/prevent rounding errors?
// Very tightly coupled to solady erc20
abstract contract ERC20Rebasing is ERC20 {
    uint256 private constant _TRANSFER_EVENT_SIGNATURE =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    uint256 private constant _TOTAL_SUPPLY_SLOT = 0x05345cdf77eb68f44c;
    uint256 private constant _BALANCE_SLOT_SEED = 0x87a211a2;

    /**
     * @dev Returns the number of tokens an internal share amount represents.
     * This amount is assumed to have 18 decimals and is divided by 10 **18 when applied.
     */
    function balancePerShare() public view virtual returns (uint128);

    // TODO: rounding
    function sharesToBalance(uint256 shares) public view returns (uint256) {
        return Math.mulDiv(shares, balancePerShare(), 1 ether);
    }

    function balanceToShares(uint256 balance) public view returns (uint256) {
        return Math.mulDiv(balance, 1 ether, balancePerShare());
    }

    /// ------------------ ERC20 ------------------

    function totalSupply() public view virtual override returns (uint256) {
        return sharesToBalance(super.totalSupply());
    }

    function maxSupply() public view virtual returns (uint256) {
        uint128 balancePerShare_ = balancePerShare();
        if (balancePerShare_ < 1 ether) {
            // TODO: replace with prbmath for muldiv18
            return Math.mulDiv(type(uint256).max, balancePerShare_, 1 ether);
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
        uint256 shares = balanceToShares(amount);
        /// @solidity memory-safe-assembly
        assembly {
            let totalSupplyBefore := sload(_TOTAL_SUPPLY_SLOT)
            let totalSupplyAfter := add(totalSupplyBefore, shares)
            // Revert if the total supply overflows.
            if lt(totalSupplyAfter, totalSupplyBefore) {
                mstore(0x00, 0xe5cfe957) // `TotalSupplyOverflow()`.
                revert(0x1c, 0x04)
            }
            // Store the updated total supply.
            sstore(_TOTAL_SUPPLY_SLOT, totalSupplyAfter)
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
        uint256 shares = balanceToShares(amount);
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
