// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

library NumberUtils {
    function addCheckOverflow(uint256 a, uint256 b) internal pure returns (bool) {
        uint256 c = 0;
        unchecked {
            c = a + b;
        }
        return c < a || c < b;
    }

    function mulCheckOverflow(uint256 a, uint256 b) internal pure returns (bool) {
        if (a == 0 || b == 0) {
            return false;
        }
        uint256 c;
        unchecked {
            c = a * b;
        }
        return c / a != b;
    }
}
