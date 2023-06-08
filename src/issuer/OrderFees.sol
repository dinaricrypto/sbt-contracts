// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

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

    /// @inheritdoc IOrderFees
    function flatFeeForOrder(address token) external view returns (uint256 flatFee) {
        uint8 decimals = IERC20Metadata(token).decimals();
        if (decimals > 18) revert DecimalsTooLarge();
        flatFee = perOrderFee;
        // adjust flat fee to token decimals
        if (decimals < 18 && flatFee != 0) {
            flatFee /= 10 ** (18 - decimals);
        }
    }

    /// @inheritdoc IOrderFees
    function percentageFeeForValue(uint256 value) external view returns (uint256) {
        // apply percentage fee
        uint64 _percentageFeeRate = percentageFeeRate;
        if (_percentageFeeRate != 0) {
            // apply fee to input value
            return PrbMath.mulDiv18(value, _percentageFeeRate);
        }
        return 0;
    }

    /// @inheritdoc IOrderFees
    function recoverInputValueFromRemaining(uint256 remainingValue) external view returns (uint256) {
        // inputValue = percentageFee + remainingValue
        // inputValue = remainingValue / (1 - percentageFeeRate)
        uint64 _percentageFeeRate = percentageFeeRate;
        if (_percentageFeeRate == 0) {
            return remainingValue;
        }
        return PrbMath.mulDiv(remainingValue, ONEHUNDRED_PERCENT, ONEHUNDRED_PERCENT - _percentageFeeRate);
    }
}
