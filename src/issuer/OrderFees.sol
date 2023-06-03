// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "solady/auth/Ownable.sol";
import "prb-math/Common.sol" as PrbMath;
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IOrderFees.sol";

/// @notice Manages fee calculations for orders.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/OrderFees.sol)
contract OrderFees is Ownable, IOrderFees {
    error FeeTooLarge();
    error DecimalsTooLarge();

    event FeeSet(uint64 perOrderFee, uint64 percentageFeeRate);

    uint64 private constant ONEHUNDRED_PERCENT = 1 ether; // 100%

    /// @dev Base fee per order in ethers decimals.
    uint64 public perOrderFee;

    /// @dev Percentage fee per order. 1 ether == 100%
    uint64 public percentageFeeRate;

    constructor(address owner, uint64 _perOrderFee, uint64 _percentageFeeRate) {
        _initializeOwner(owner);

        if (_percentageFeeRate > ONEHUNDRED_PERCENT) revert FeeTooLarge();

        perOrderFee = _perOrderFee;
        percentageFeeRate = _percentageFeeRate;
    }

    /// @dev Sets the base and percentage fees.
    function setFees(uint64 _perOrderFee, uint64 _percentageFeeRate) external onlyOwner {
        if (_percentageFeeRate > ONEHUNDRED_PERCENT) revert FeeTooLarge();

        perOrderFee = _perOrderFee;
        percentageFeeRate = _percentageFeeRate;
        emit FeeSet(_perOrderFee, _percentageFeeRate);
    }

    function flatFeeForOrder(address token) public view returns (uint256 flatFee) {
        uint8 decimals = IERC20Metadata(token).decimals();
        if (decimals > 18) revert DecimalsTooLarge();
        flatFee = perOrderFee;
        // adjust flat fee to token decimals
        if (decimals < 18 && flatFee != 0) {
            flatFee /= 10 ** (18 - decimals);
        }
    }

    /// @inheritdoc IOrderFees
    function feesForOrderUpfront(address token, uint256 value)
        external
        view
        returns (uint256 flatFee, uint256 percentageFee)
    {
        flatFee = flatFeeForOrder(token);
        // apply percentage fee
        uint64 _percentageFeeRate = percentageFeeRate;
        if (_percentageFeeRate != 0 && value > flatFee) {
            // apply fee to order value, not input value
            percentageFee = PrbMath.mulDiv(value - flatFee, _percentageFeeRate, ONEHUNDRED_PERCENT + _percentageFeeRate);
        }
    }

    function feesOnProceeds(address token, uint256 value)
        external
        view
        returns (uint256 flatFee, uint256 percentageFee)
    {
        flatFee = flatFeeForOrder(token);
        // apply percentage fee
        uint64 _percentageFeeRate = percentageFeeRate;
        if (_percentageFeeRate != 0 && value > flatFee) {
            // apply fee to remaining input value
            percentageFee = PrbMath.mulDiv18(value - flatFee, _percentageFeeRate);
        }
    }

    function inputValueForOrderValueUpfrontFees(address token, uint256 orderValue)
        external
        view
        returns (uint256 inputValue)
    {
        inputValue = flatFeeForOrder(token);
        uint64 _percentageFeeRate = percentageFeeRate;
        if (_percentageFeeRate != 0) {
            inputValue += PrbMath.mulDiv18(orderValue, ONEHUNDRED_PERCENT + _percentageFeeRate);
        }
    }
}
