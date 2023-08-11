// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

/// @notice Base contract for verifying price attestations from trusted oracles
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/metatx/PriceAttestationConsumer.sol)
/// @dev Oracles sign prices and publish them to be consumed by contracts that inherit from this one
abstract contract PriceAttestationConsumer is Ownable, EIP712 {
    /// ------------------------------- Types -------------------------------

    struct PriceAttestation {
        // Address of token whose price is being attested
        address token;
        // Price of 1 `token` in wei, accounting for token decimals
        uint256 price;
        // Timestamp when price was recorded
        uint64 timestamp;
        uint256 chainId;
        // ECDSA signature of the oracle publishing the price.
        bytes signature;
    }

    error FuturePrice();
    error StalePrice();
    error WrongChainId();
    error NotTrustedOracle();

    event TrustedOracleSet(address indexed oracle, bool isTrusted);
    event PriceRecencyThresholdSet(uint256 threshold);

    /// ------------------------------- Constants -------------------------------

    string private constant PRICE_ATTESTATION_TYPE =
        "PriceAttestation(address token,uint256 price,uint64 timestamp,uint256 chainId)";
    bytes32 private constant PRICE_ATTESTATION_TYPEHASH = keccak256(abi.encodePacked(PRICE_ATTESTATION_TYPE));

    /// ------------------------------- Storage -------------------------------

    /// @notice Is the account a trusted oracle?
    mapping(address => bool) public isTrustedOracle;

    /// @notice How old can a price be before it is considered stale?
    uint64 public priceRecencyThreshold;

    /// ------------------------------- Initialization -------------------------------

    constructor(uint64 _priceRecencyThreshold) {
        priceRecencyThreshold = _priceRecencyThreshold;
    }

    /// ------------------------------- Administration -------------------------------

    /// @notice Sets the trusted oracle status of an account
    function setTrustedOracle(address oracle, bool isTrusted) external onlyOwner {
        isTrustedOracle[oracle] = isTrusted;
        emit TrustedOracleSet(oracle, isTrusted);
    }

    /// @notice Sets the price recency threshold
    function setPriceRecencyThreshold(uint64 threshold) external onlyOwner {
        priceRecencyThreshold = threshold;
        emit PriceRecencyThresholdSet(threshold);
    }

    /// ------------------------------- Price Verification -------------------------------

    /// @notice Verifies a price attestation
    function _verifyPriceAttestation(PriceAttestation calldata attestation) internal view {
        if (attestation.chainId != block.chainid) revert WrongChainId();
        if (attestation.timestamp > block.timestamp) revert FuturePrice();
        if (block.timestamp > attestation.timestamp + priceRecencyThreshold) revert StalePrice();

        // Compute the EIP-712 typed data hash and recover signer
        bytes32 typedDataHash = _hashTypedDataV4(priceAttestationHash(attestation));
        // get signer
        address signer = ECDSA.recover(typedDataHash, attestation.signature);
        if (!isTrustedOracle[signer]) revert NotTrustedOracle();
    }

    function priceAttestationHash(PriceAttestation calldata attestation) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                PRICE_ATTESTATION_TYPEHASH,
                attestation.token,
                attestation.price,
                attestation.timestamp,
                attestation.chainId
            )
        );
    }
}
