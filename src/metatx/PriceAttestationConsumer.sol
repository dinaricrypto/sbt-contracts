// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

/// @notice Base contract for verifying price attestations from trusted oracles
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/metatx/PriceAttestationConsumer.sol)
abstract contract PriceAttestationConsumer {
    struct PriceAttestation {
        address token;
        // Price of 1 `token` in USD with ethers decimals
        uint256 price;
        // Timestamp when price was recorded
        uint256 timestamp;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    error StalePrice();
    error NotTrustedOracle();

    mapping(address => bool) public isTrustedOracle;

    uint256 public priceRecencyThreshold;

    function setTrustedOracle(address oracle, bool isTrusted) external {
        isTrustedOracle[oracle] = isTrusted;
    }

    function setPriceRecencyThreshold(uint256 threshold) external {
        priceRecencyThreshold = threshold;
    }

    function _verifyPriceAttestation(PriceAttestation memory attestation) internal view {
        if (attestation.timestamp + priceRecencyThreshold > block.timestamp) revert StalePrice();
        address signer = ECDSA.recover(
            keccak256(abi.encodePacked(attestation.token, attestation.price, attestation.timestamp)),
            attestation.v,
            attestation.r,
            attestation.s
        );
        if (!isTrustedOracle[signer]) revert NotTrustedOracle();
    }
}
