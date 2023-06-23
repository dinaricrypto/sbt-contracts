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
        view
        returns (bytes32)
    {
        address user = msg.sender;
        address issuer = _issuer; // issuer address
        address paymentToken = _paymentToken; // payment token address
        bytes memory data = _data; // encoded function call
        uint256 nonce = _nonce;

        SigUtils.MetaTransaction memory metaTx = SigUtils.MetaTransaction({
            user: user,
            to: issuer,
            paymentToken: paymentToken,
            data: data,
            nonce: nonce,
            v: 0,
            r: bytes32(0),
            s: bytes32(0)
        });

        bytes32 hashToSign = sigUtils.getHashToSign(metaTx);

        // hashToSign is the hash that should be signed by the user
        return hashToSign;
    }

    function submitMetaTransaction(SigUtils.MetaTransaction memory metaTx, uint8 v, bytes32 r, bytes32 s) public {
        // Validate signature
        bytes32 digest = sigUtils.getTypedDataHashForMetaTransaction(metaTx);
        address signer = ecrecover(digest, v, r, s);
        require(signer == metaTx.user, "Invalid signature");

        // Execute transaction
        (bool success,) = metaTx.to.call(metaTx.data);
        require(success, "Meta-transaction call failed");
    }
}
