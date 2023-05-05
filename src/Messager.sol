// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "solady/utils/SignatureCheckerLib.sol";

contract Messager {
    error InvalidSignature();

    event MessageSent(address indexed from, address indexed to, string message);

    function hashMessage(string calldata message) public pure returns (bytes32) {
        return keccak256(abi.encode(message));
    }

    function sendMessage(address from, address to, string calldata message, uint8 v, bytes32 r, bytes32 s) external {
        // Verify message signed by from
        if (!SignatureCheckerLib.isValidSignatureNow(from, hashMessage(message), v, r, s)) revert InvalidSignature();
        emit MessageSent(from, to, message);
    }
}
