// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "prb-math/Common.sol" as PrbMath;
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IOrderFees.sol";

/// @notice Manages fee calculations for orders.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/issuer/OrderFees.sol)
contract OrderFees is Ownable2Step, IOrderFees {
    // TODO: calcs fail for type(uint256).max. Can the effective range be increased by moving to bips?
    error FeeTooLarge();
    error DecimalsTooLarge();

    event FeeSet(uint64 perOrderFee, uint64 percentageFeeRate);

    /// @dev 1 ether == 100%
    uint64 private constant ONEHUNDRED_PERCENT = 1 ether;

    /// @notice Base fee per order in ethers decimals
    uint64 public perOrderFee;

    /// @notice Percentage fee per order in ethers decimals
    uint64 public percentageFeeRate;

    constructor(address owner, uint64 _perOrderFee, uint64 _percentageFeeRate) {
        _transferOwnership(owner);

        if (_percentageFeeRate >= ONEHUNDRED_PERCENT) revert FeeTooLarge();

        perOrderFee = _perOrderFee;
        percentageFeeRate = _percentageFeeRate;
    }

    /// @notice Set the base and percentage fees
    /// @param _perOrderFee Base flat fee per order in ethers decimals
    /// @param _percentageFeeRate Percentage fee per order in ethers decimals
    function setFees(uint64 _perOrderFee, uint64 _percentageFeeRate) external onlyOwner {
        if (_percentageFeeRate >= ONEHUNDRED_PERCENT) revert FeeTooLarge();

        perOrderFee = _perOrderFee;
        percentageFeeRate = _percentageFeeRate;
        emit FeeSet(_perOrderFee, _percentageFeeRate);
    }

    /// @notice Calculates flat fee for an order
    /// @param token Token for order
    function flatFeeForOrder(address token) external view returns (uint256 flatFee) {
        uint8 decimals = IERC20Metadata(token).decimals();
        if (decimals > 18) revert DecimalsTooLarge();
        flatFee = perOrderFee;
        // adjust flat fee to token decimals
        if (decimals < 18 && flatFee != 0) {
            flatFee /= 10 ** (18 - decimals);
        }
    }

    /// @notice Calculates percentage fee for an order
    /// @param value Value of order subject to percentage fee
    function percentageFeeForValue(uint256 value) external view returns (uint256) {
        // apply percentage fee
        uint64 _percentageFeeRate = percentageFeeRate;
        if (_percentageFeeRate != 0) {
            // apply fee to input value
            return PrbMath.mulDiv18(value, _percentageFeeRate);
        }
        return 0;
    }

    /// @notice Calculates percentage fee for an order as if fee was added to order value
    /// @param value Value of order subject to percentage fee
    function percentageFeeOnRemainingValue(uint256 value) external view returns (uint256) {
        // inputValue - percentageFee = remainingValue
        // percentageFee = percentageFeeRate * remainingValue
        uint64 _percentageFeeRate = percentageFeeRate;
        if (_percentageFeeRate != 0) {
            // apply fee to order value, not input value
            return PrbMath.mulDiv(value, _percentageFeeRate, ONEHUNDRED_PERCENT + _percentageFeeRate);
        }
        return 0;
    }

    /// @notice Recovers input value needed to achieve a given remaining value after fees
    /// @param remainingValue Remaining value after fees
    function recoverInputValueFromFee(uint256 remainingValue) external view returns (uint256) {
        // inputValue = percentageFee + remainingValue
        // inputValue = remainingValue / (1 - percentageFeeRate)
        uint64 _percentageFeeRate = percentageFeeRate;
        if (_percentageFeeRate == 0) {
            return remainingValue;
        }
        return PrbMath.mulDiv(remainingValue, ONEHUNDRED_PERCENT, ONEHUNDRED_PERCENT - _percentageFeeRate);
    }

    /// @notice Recovers input value needed to achieve a given remaining value as if fee was added to order value
    /// @param remainingValue Remaining value after fees
    function recoverInputValueFromFeeOnRemaining(uint256 remainingValue) external view returns (uint256) {
        // inputValue = percentageFee + remainingValue
        // inputValue = remainingValue * (1 + percentageFeeRate)
        uint64 _percentageFeeRate = percentageFeeRate;
        if (_percentageFeeRate == 0) {
            return remainingValue;
        }
        return PrbMath.mulDiv18(remainingValue, ONEHUNDRED_PERCENT + _percentageFeeRate);
    }
}
