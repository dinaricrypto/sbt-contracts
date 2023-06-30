// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "prb-math/Common.sol" as PrbMath;
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IOrderFees} from "./IOrderFees.sol";

/// @notice Manages fee calculations for orders.
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/issuer/OrderFees.sol)
contract OrderFees is Ownable2Step, IOrderFees {
    /// ------------------ Types ------------------ ///

    /// @dev Fee is too large
    error FeeTooLarge();
    /// @dev Decimals are too large
    error DecimalsTooLarge();

    /// @dev Emitted when `perOrderFee` and `percentageFeeRate` are set
    event FeeSet(uint64 perOrderFee, uint64 percentageFeeRate);

    /// ------------------ Constants ------------------ ///

    /// @dev 1 ether == 100%
    uint64 private constant _ONEHUNDRED_PERCENT = 1 ether;

    /// ------------------ State ------------------ ///

    /// @notice Flat fee per order in ethers decimals
    uint64 public perOrderFee;

    /// @notice Percentage fee take per order in ethers decimals
    uint64 public percentageFeeRate;

    /// ------------------ Initialization ------------------ ///

    /// @notice Initialize fees
    /// @param owner Owner of contract
    /// @param _perOrderFee Base flat fee per order in ethers decimals
    /// @param _percentageFeeRate Percentage fee take per order in ethers decimals
    /// @dev Percentage fee cannot be 100% or more
    constructor(address owner, uint64 _perOrderFee, uint64 _percentageFeeRate) {
        // Check percentage fee is less than 100%
        if (_percentageFeeRate >= _ONEHUNDRED_PERCENT) revert FeeTooLarge();

        // Set owner
        _transferOwnership(owner);

        // Initialize fees
        perOrderFee = _perOrderFee;
        percentageFeeRate = _percentageFeeRate;
    }

    /// ------------------ Update ------------------ ///

    /// @notice Set the base and percentage fees
    /// @param _perOrderFee Base flat fee per order in ethers decimals
    /// @param _percentageFeeRate Percentage fee per order in ethers decimals
    /// @dev Only callable by owner
    function setFees(uint64 _perOrderFee, uint64 _percentageFeeRate) external onlyOwner {
        // Check percentage fee is less than 100%
        if (_percentageFeeRate >= _ONEHUNDRED_PERCENT) revert FeeTooLarge();

        // Update fees
        perOrderFee = _perOrderFee;
        percentageFeeRate = _percentageFeeRate;
        // Emit new fees
        emit FeeSet(_perOrderFee, _percentageFeeRate);
    }

    /// ------------------ Fee Calculation ------------------ ///

    /// @inheritdoc IOrderFees
    function flatFeeForOrder(address token) external view returns (uint256 flatFee) {
        // Query token decimals from token contract
        // This could revert if the token is not IERC20Metadata
        uint8 decimals = IERC20Metadata(token).decimals();
        // Decimals over 18 are not supported
        if (decimals > 18) revert DecimalsTooLarge();
        // Start with base flat fee
        flatFee = perOrderFee;
        // Adjust flat fee to token decimals if necessary
        if (decimals < 18 && flatFee != 0) {
            flatFee /= 10 ** (18 - decimals);
        }
    }

    /// @inheritdoc IOrderFees
    function percentageFeeForValue(uint256 value) external view returns (uint256) {
        // Get base percentage fee rate
        uint64 _percentageFeeRate = percentageFeeRate;
        // If percentage fee rate is non-zero, use it, else return 0
        if (_percentageFeeRate != 0) {
            // Apply fee to input value
            return PrbMath.mulDiv18(value, _percentageFeeRate);
        }
        return 0;
    }

    /// @inheritdoc IOrderFees
    function recoverInputValueFromRemaining(uint256 remainingValue) external view returns (uint256) {
        // Get base percentage fee rate
        uint64 _percentageFeeRate = percentageFeeRate;
        // If percentage fee rate is zero, return input unchanged
        if (_percentageFeeRate == 0) {
            return remainingValue;
        }
        // inputValue = percentageFee + remainingValue
        // inputValue = remainingValue / (1 - percentageFeeRate)
        return PrbMath.mulDiv(remainingValue, _ONEHUNDRED_PERCENT, _ONEHUNDRED_PERCENT - _percentageFeeRate);
    }
}
