// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "solady/src/tokens/ERC4626.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "solady/src/utils/SafeCastLib.sol";

abstract contract xERC4626 is ERC4626 {
    using SafeCastLib for *;

    /// @notice the maximum length of a rewards cycle
    uint32 public immutable rewardsCycleLength;

    /// @notice the effective start of the current cycle
    uint32 public lastSync;

    /// @notice the end of the current cycle. Will always be evenly divisible by `rewardsCycleLength`.
    uint32 public rewardsCycleEnd;

    /// @notice the amount of rewards distributed in a the most recent cycle.
    uint192 public lastRewardAmount;

    uint256 internal storedTotalAssets;

    /// @dev thrown when syncing before cycle ends.
    error SyncError();
    /// @dev emit every time a new rewards cycle starts

    event NewRewardsCycle(uint32 indexed cycleEnd, uint256 rewardAmount);

    constructor(uint32 _rewardsCycleLength) {
        rewardsCycleLength = _rewardsCycleLength;
        // seed initial rewardsCycleEnd
        // slither-disable-next-line divide-before-multiply
        rewardsCycleEnd = (block.timestamp.toUint32() / rewardsCycleLength) * rewardsCycleLength;
    }

    /// @notice Compute the amount of tokens available to share holders.
    ///         Increases linearly during a reward distribution period from the sync call, not the cycle start.
    function totalAssets() public view override returns (uint256) {
        // cache global vars
        uint256 storedTotalAssets_ = storedTotalAssets;
        uint192 lastRewardAmount_ = lastRewardAmount;
        uint32 rewardsCycleEnd_ = rewardsCycleEnd;
        uint32 lastSync_ = lastSync;

        if (block.timestamp >= rewardsCycleEnd_) {
            // no rewards or rewards fully unlocked
            // entire reward amount is available
            return storedTotalAssets_ + lastRewardAmount_;
        }

        // rewards not fully unlocked
        // add unlocked rewards to stored total
        uint256 unlockedRewards = (lastRewardAmount_ * (block.timestamp - lastSync_)) / (rewardsCycleEnd_ - lastSync_);
        return storedTotalAssets_ + unlockedRewards;
    }

    // Update storedTotalAssets on withdraw/redeem
    function _beforeWithdraw(uint256 amount, uint256 shares) internal virtual override {
        super._beforeWithdraw(amount, shares);
        storedTotalAssets -= amount;
    }

    // Update storedTotalAssets on deposit/mint
    function _afterDeposit(uint256 amount, uint256 shares) internal virtual override {
        storedTotalAssets += amount;
        super._afterDeposit(amount, shares);
    }

    /// @notice Distributes rewards to xERC4626 holders.
    /// All surplus `asset` balance of the contract over the internal balance becomes queued for the next cycle.
    function syncRewards() public virtual {
        uint192 lastRewardAmount_ = lastRewardAmount;
        uint32 timestamp = block.timestamp.toUint32();

        if (timestamp < rewardsCycleEnd) revert SyncError();

        uint256 storedTotalAssets_ = storedTotalAssets;
        uint256 nextRewards = IERC20(asset()).balanceOf(address(this)) - storedTotalAssets_ - lastRewardAmount_;

        storedTotalAssets = storedTotalAssets_ + lastRewardAmount_; // SSTORE

        // slither-disable-next-line divide-before-multiply
        uint32 end = ((timestamp + rewardsCycleLength) / rewardsCycleLength) * rewardsCycleLength;

        // Combined single SSTORE
        lastRewardAmount = nextRewards.toUint192();
        lastSync = timestamp;
        rewardsCycleEnd = end;

        emit NewRewardsCycle(end, nextRewards);
    }
}
