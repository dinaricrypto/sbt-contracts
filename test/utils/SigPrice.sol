// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract SigPrice {
    bytes32 internal immutable DOMAIN_SEPARATOR;
    string private constant PRICE_ATTESTATION_TYPE =
        "PriceAttestation(address token,uint256 price,uint64 timestamp,uint256 chainId)";
    bytes32 public constant PRICE_ATTESTATION_TYPEHASH = keccak256(abi.encodePacked(PRICE_ATTESTATION_TYPE));

    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
    }

    struct PriceAttestation {
        address token;
        uint256 price;
        uint64 timestamp;
        uint256 chainId;
    }

    function _getPriceAttestationStructHash(PriceAttestation memory priceAttestation) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                PRICE_ATTESTATION_TYPEHASH,
                priceAttestation.token,
                priceAttestation.price,
                priceAttestation.timestamp,
                priceAttestation.chainId
            )
        );
    }

    function getTypedDataHashForPriceAttestation(PriceAttestation memory priceAttestation)
        public
        view
        returns (bytes32)
    {
        return
            keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, _getPriceAttestationStructHash(priceAttestation)));
    }
}
