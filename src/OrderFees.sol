// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "solady/auth/Ownable.sol";
import "prb-math/Common.sol" as PrbMath;
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "./IOrderFees.sol";

/// @notice Manages fee calculations for orders.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/OrderFees.sol)
contract OrderFees is Ownable, IOrderFees {
    error FeeTooLarge();

    event FeeSet(uint64 perOrderFee, uint64 percentageFee);

    uint64 private constant MAX_PERCENTAGE_FEE = 1 ether; // 100%

    /// @dev Base fee per order in ethers decimals.
    uint64 public perOrderFee;

    /// @dev Percentage fee per order. 1 ether == 100%
    uint64 public percentageFee;

    constructor(address owner, uint64 _perOrderFee, uint64 _percentageFee) {
        _initializeOwner(owner);

        if (_percentageFee > MAX_PERCENTAGE_FEE) revert FeeTooLarge();

        perOrderFee = _perOrderFee;
        percentageFee = _percentageFee;
    }

    /// @dev Sets the base and percentage fees.
    function setFees(uint64 _perOrderFee, uint64 _percentageFee) external onlyOwner {
        if (_percentageFee > MAX_PERCENTAGE_FEE) revert FeeTooLarge();

        perOrderFee = _perOrderFee;
        percentageFee = _percentageFee;
        emit FeeSet(_perOrderFee, _percentageFee);
    }

    /// @inheritdoc IOrderFees
    function feesForOrder(address token, bool, uint256 value) external view returns (uint256 fee) {
        fee = perOrderFee;
        uint8 decimals = IERC20Metadata(token).decimals();
        if (decimals < 18) {
            fee /= 10 ** (18 - decimals);
        } else if (decimals > 18) {
            fee *= 10 ** (decimals - 18);
        }
        uint64 _percentageFee = percentageFee;
        if (_percentageFee != 0 && value != 0) {
            fee += PrbMath.mulDiv18(value, _percentageFee);
        }
    }
}
