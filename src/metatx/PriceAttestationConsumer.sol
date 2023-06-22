// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

/// @notice Base contract for verifying price attestations from trusted oracles
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/metatx/PriceAttestationConsumer.sol)
abstract contract PriceAttestationConsumer is Ownable {
    struct PriceAttestation {
        // Address of token whose price is being attested
        address token;
        // Price of 1 `token` in USD with ethers decimals
        uint256 price;
        // Timestamp when price was recorded
        uint256 timestamp;
        // ECDSA signature parameter v
        uint8 v;
        // ECDSA signature parameter r
        bytes32 r;
        // ECDSA signature parameter s
        bytes32 s;
    }

    error StalePrice();
    error NotTrustedOracle();

    /// @notice Is the account a trusted oracle?
    mapping(address => bool) public isTrustedOracle;

    /// @notice How old can a price be before it is considered stale?
    uint256 public priceRecencyThreshold;

    constructor(uint256 _priceRecencyThreshold) {
        priceRecencyThreshold = _priceRecencyThreshold;
    }

    /// @notice Sets the trusted oracle status of an account
    function setTrustedOracle(address oracle, bool isTrusted) external onlyOwner {
        isTrustedOracle[oracle] = isTrusted;
    }

    /// @notice Sets the price recency threshold
    function setPriceRecencyThreshold(uint256 threshold) external onlyOwner {
        priceRecencyThreshold = threshold;
    }

    /// @notice Verifies a price attestation
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
