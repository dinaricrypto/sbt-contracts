// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./SigUtils.sol";

contract MetaProcessor {
    SigUtils sigUtils;

    constructor(SigUtils _sigUtils) {
        sigUtils = _sigUtils;
    }

    function prepareMetaTransaction(address _issuer, address _paymentToken, bytes memory _data, uint256 _nonce)
        public
        returns (bytes32)
    {
        address user = msg.sender;
        address issuer = _issuer; // Example address
        address paymentToken = _paymentToken; // Example address
        bytes memory data = _data; // Example data
        uint256 nonce = _nonce;

        SigUtils.MetaTransaction memory metaTx = SigUtils.MetaTransaction({
            user: user,
            to: issuer,
            paymentToken: paymentToken,
            data: data,
            nonce: nonce,
            v: 0, // user will sign this
            r: bytes32(0), // Not yet known
            s: bytes32(0) // Not yet known
        });

        bytes32 hashToSign = sigUtils.getHashToSign(metaTx);

        // hashToSign is the hash that should be signed by the user
        return hashToSign;
    }
}
