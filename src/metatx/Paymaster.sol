// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseRelayRecipient} from "gsnV3/contracts/src/BaseRelayRecipient.sol";
import "gsnV3/contracts/src/utils/GsnTypes.sol";

abstract contract Paymaster is BaseRelayRecipient {
    /**
     * @notice Mapping to keep track of each user's opt-in status for using the paymaster.
     * @dev Key is user's address, and value is a boolean indicating whether the user has opted in.
     */
    mapping(address => bool) public isUserOptedIn;

    error UserNotOptedIn();

    constructor(address forwarder) {
        _setTrustedForwarder(forwarder);
    }

    /**
     * @notice Sets the user's opt-in status for using the paymaster.
     * @param optIn Boolean indicating whether the user wants to opt in (true) or opt out (false) of the paymaster.
     */
    function setUserOptInStatus(bool optIn) external {
        isUserOptedIn[msg.sender] = optIn;
    }

    /**
     * @notice Disables the user's opt-in status, effectively opting them out of using the paymaster.
     */
    function disableUserOptIn() external {
        isUserOptedIn[msg.sender] = false;
    }

    /**
     * @notice Approves a relayed call if it meets certain conditions.
     * @param relayRequest Data structure that contains information about the relayed call.
     * @param deadline The timestamp by which the approval signature must be used, otherwise it is considered expired.
     * @param v ECDSA signature parameter v.
     * @param r ECDSA signature parameter r.
     * @param s ECDSA signature parameter s.
     * @return Returns empty bytes if the relayed call is approved, reverts otherwise.
     */
    function approveRelayCall(
        GsnTypes.RelayRequest calldata relayRequest,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external view returns (bytes memory) {
        // Check if the transaction has been signed by the user
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Paymaster")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("RelayRequest(GSNTypes.RelayRequest relayRequest,uint256 deadline)"), relayRequest, deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Recover the signer's address from the signature
        address signer = ecrecover(digest, v, r, s);

        // Check if the signer has opted in to use the Paymaster
        if (!isUserOptedIn[signer]) {
            revert UserNotOptedIn();
        }
        // Check if the deadline has not passed
        require(block.timestamp <= deadline, "Signature expired");

        return ""; // No context needed, return empty bytes
    }
}
