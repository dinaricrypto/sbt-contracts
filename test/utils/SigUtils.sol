contract SigUtils {
    bytes32 internal DOMAIN_SEPARATOR;

    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
    }

    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    bytes32 public constant META_TRANSACTION_TYPEHASH =
        keccak256("MetaTransaction(address user,address to,address paymentToken,bytes data,uint256 nonce)");

    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }

    struct MetaTransaction {
        address user;
        address to;
        address paymentToken;
        bytes data;
        uint256 nonce;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function getMetaTransactionStructHash(MetaTransaction memory _metaTx) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                META_TRANSACTION_TYPEHASH,
                _metaTx.user,
                _metaTx.to,
                _metaTx.paymentToken,
                keccak256(_metaTx.data),
                _metaTx.nonce,
                _metaTx.v,
                _metaTx.r,
                _metaTx.s
            )
        );
    }

    function getHashToSign(MetaTransaction memory _metaTx) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                META_TRANSACTION_TYPEHASH,
                _metaTx.user,
                _metaTx.to,
                _metaTx.paymentToken,
                keccak256(_metaTx.data),
                _metaTx.nonce
            )
        );
    }

    function getStructHash(Permit memory _permit) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(PERMIT_TYPEHASH, _permit.owner, _permit.spender, _permit.value, _permit.nonce, _permit.deadline)
        );
    }

    function getTypedDataHash(Permit memory _permit) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, getStructHash(_permit)));
    }

    function getTypedDataHashForMetaTransaction(MetaTransaction memory _metaTx) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, getMetaTransactionStructHash(_metaTx)));
    }
}
