// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

library OracleLib {
    function pairIndex(address assetToken, address paymentToken) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(assetToken, paymentToken));
    }
}
