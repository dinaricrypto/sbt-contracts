// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {PriceAttestationConsumer} from "../../src/forwarder/PriceAttestationConsumer.sol";

contract SigMeta {
    bytes32 internal immutable DOMAIN_SEPARATOR;
    bytes private constant SIGNEDPRICEATTESTATION_TYPE = abi.encodePacked(
        "PriceAttestation(address token,uint256 price,uint64 timestamp,uint256 chainId,bytes signature)"
    );
    bytes32 private constant SIGNEDPRICEATTESTATION_TYPEHASH = keccak256(SIGNEDPRICEATTESTATION_TYPE);
    bytes private constant FORWARDREQUEST_TYPE = abi.encodePacked(
        "ForwardRequest(address user,address to,bytes data,uint64 deadline,uint256 nonce,PriceAttestation paymentTokenOraclePrice)",
        SIGNEDPRICEATTESTATION_TYPE
    );
    bytes32 private constant FORWARDREQUEST_TYPEHASH = keccak256(FORWARDREQUEST_TYPE);

    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
    }

    struct ForwardRequest {
        address user;
        address to;
        bytes data;
        uint64 deadline;
        uint256 nonce;
        PriceAttestationConsumer.PriceAttestation paymentTokenOraclePrice;
    }

    function _signedPriceAttestationHash(PriceAttestationConsumer.PriceAttestation calldata priceAttestation)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                SIGNEDPRICEATTESTATION_TYPEHASH,
                priceAttestation.token,
                priceAttestation.price,
                priceAttestation.timestamp,
                priceAttestation.chainId,
                keccak256(priceAttestation.signature)
            )
        );
    }

    function _hashForwardRequest(ForwardRequest calldata metaTx) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                FORWARDREQUEST_TYPEHASH,
                metaTx.user,
                metaTx.to,
                keccak256(metaTx.data),
                metaTx.deadline,
                metaTx.nonce,
                _signedPriceAttestationHash(metaTx.paymentTokenOraclePrice)
            )
        );
    }

    function getHashToSign(ForwardRequest calldata metaTx) public view returns (bytes32) {
        // This uses EIP712's _hashTypedDataV4 which conforms to the standard
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, _hashForwardRequest(metaTx)));
    }
}
