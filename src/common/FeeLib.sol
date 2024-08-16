// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "prb-math/Common.sol" as PrbMath;

library FeeLib {
    // 1_000_000 == 100%
    uint24 private constant _ONEHUNDRED_PERCENT = 1_000_000;

    uint64 private constant _FLAT_FEE_DECIMALS = 8;

    /// @dev Fee is too large
    error FeeTooLarge();
    /// @dev Decimals are too large
    error DecimalsTooLarge();

    function checkPercentageFeeRate(uint24 _percentageFeeRate) internal pure {
        if (_percentageFeeRate >= _ONEHUNDRED_PERCENT) revert FeeTooLarge();
    }

    function percentageFeeForValue(uint256 value, uint24 percentageFeeRate) internal pure returns (uint256) {
        if (percentageFeeRate >= _ONEHUNDRED_PERCENT) revert FeeTooLarge();
        return percentageFeeRate != 0 ? PrbMath.mulDiv(value, percentageFeeRate, _ONEHUNDRED_PERCENT) : 0;
    }

    function flatFeeForOrder(uint8 paymentTokenDecimals, uint64 perOrderFee) internal pure returns (uint256 flatFee) {
        if (paymentTokenDecimals > 18) revert DecimalsTooLarge();
        if (perOrderFee == 0) return 0;
        if (paymentTokenDecimals > _FLAT_FEE_DECIMALS) {
            flatFee = perOrderFee * 10 ** (paymentTokenDecimals - _FLAT_FEE_DECIMALS);
        } else if (paymentTokenDecimals < _FLAT_FEE_DECIMALS) {
            flatFee = perOrderFee / 10 ** (_FLAT_FEE_DECIMALS - paymentTokenDecimals);
        } else {
            flatFee = perOrderFee;
        }
    }

    function applyPercentageFee(uint24 percentageFeeRate, uint256 orderValue) internal pure returns (uint256) {
        return percentageFeeRate != 0 ? PrbMath.mulDiv(orderValue, percentageFeeRate, _ONEHUNDRED_PERCENT) : 0;
    }
}
