// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

/// @notice Contract interface for verifying price attestations from trusted oracles
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/forwarder/IPriceAttestationConsumer.sol)
interface IPriceAttestationConsumer {
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

    /// @notice Is the account a trusted oracle?
    function isTrustedOracle(address account) external view returns (bool);

    /// @notice How old can a price be before it is considered stale?
    function priceRecencyThreshold() external view returns (uint64);
}
