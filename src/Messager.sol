// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SignatureChecker} from "openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";

contract Messager {
    error InvalidSignature();

    event MessageSent(address indexed from, address indexed to, string message);

    function hashMessage(string calldata message) public pure returns (bytes32) {
        return keccak256(abi.encode(message));
    }

    function sendMessage(address from, address to, string calldata message, uint8 v, bytes32 r, bytes32 s) external {
        // Verify message signed by from
        if (!SignatureChecker.isValidSignatureNow(from, hashMessage(message), abi.encodePacked(r, s, v))) {
            revert InvalidSignature();
        }
        emit MessageSent(from, to, message);
    }
}
