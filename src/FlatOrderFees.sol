// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "solady/auth/Ownable.sol";
import "prb-math/Common.sol" as PrbMath;
import "./IOrderFees.sol";

/// @notice Manages fee calculations for orders.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/OrderFees.sol)
contract FlatOrderFees is Ownable, IOrderFees {
    error FeeTooLarge();

    event FeeSet(uint64 fee);

    uint64 private constant MAX_FEE = 1 ether; // 100%

    uint64 public fee;

    constructor(address owner, uint64 _fee) {
        _initializeOwner(owner);

        fee = _fee;
    }

    function setFee(uint64 _fee) external onlyOwner {
        if (_fee > MAX_FEE) revert FeeTooLarge();

        fee = _fee;
        emit FeeSet(_fee);
    }

    function getFees(address, bool, uint256 value) external view returns (uint256) {
        uint64 _fee = fee;
        if (_fee == 0) {
            return 0;
        } else {
            return PrbMath.mulDiv18(value, _fee);
        }
    }
}
