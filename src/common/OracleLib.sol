// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "./NumberUtils.sol";
import {mulDiv} from "prb-math/Common.sol";

library OracleLib {
    function pairIndex(address assetToken, address paymentToken) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(assetToken, paymentToken));
    }

    function calculatePrice(uint256 assetTokenQuantity, uint256 paymentTokenQuantity, uint8 paymentTokenDecimals)
        internal
        pure
        returns (uint256)
    {
        uint256 decimalMult = 10 ** (18 - paymentTokenDecimals);
        if (NumberUtils.mulDivCheckOverflow(paymentTokenQuantity, decimalMult, assetTokenQuantity)) return 0;
        return mulDiv(paymentTokenQuantity, decimalMult, assetTokenQuantity);
    }
}
