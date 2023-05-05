// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "solady/auth/Ownable.sol";
import "prb-math/Common.sol" as PrbMath;
import "./IOrderFees.sol";

/// @notice Manages fee calculations for orders.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/OrderFees.sol)
contract FlatOrderFees is Ownable, IOrderFees {
    error FeeTooLarge();

    event SellerFeeSet(uint64 fee);
    event BuyerFeeSet(uint64 fee);

    uint64 private constant MAX_FEE = 1 ether; // 100%

    uint64 public sellerFee;
    uint64 public buyerFee;

    constructor() {
        _initializeOwner(msg.sender);
    }

    function setSellerFee(uint64 fee) external onlyOwner {
        if (fee > MAX_FEE) revert FeeTooLarge();

        sellerFee = fee;
        emit SellerFeeSet(fee);
    }

    function setBuyerFee(uint64 fee) external onlyOwner {
        if (fee > MAX_FEE) revert FeeTooLarge();

        buyerFee = fee;
        emit BuyerFeeSet(fee);
    }

    function getFees(bool sell, uint256 value) external view returns (uint256) {
        uint64 fee = sell ? sellerFee : buyerFee;
        if (fee == 0) {
            return 0;
        } else {
            return PrbMath.mulDiv18(value, fee);
        }
    }
}
