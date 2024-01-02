// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IOrderProcessor} from "../../src/orders/IOrderProcessor.sol";

contract SigMetaUtils {
    bytes32 internal immutable DOMAIN_SEPARATOR;

    bytes private constant ORDER_TYPE = abi.encodePacked(
        "Order(address recipient,address assetToken,address paymentToken,bool sell,uint256 orderType,uint256 assetTokenQuantity,uint256 paymentTokenQuantity,uint256 price,uint256 tif,address splitRecipient,uint256 splitAmount)"
    );

    bytes32 private constant ORDER_TYPEHASH = keccak256(ORDER_TYPE);

    bytes private constant ORDER_FORWARDREQUEST_TYPE =
        abi.encodePacked("OrderForwardRequest(address user,address to,bytes32 orderHash,uint64 deadline,uint256 nonce)");

    bytes32 private constant ORDER_FORWARDREQUEST_TYPEHASH = keccak256(ORDER_FORWARDREQUEST_TYPE);

    bytes private constant CANCEL_FORWARDREQUEST_TYPE =
        abi.encodePacked("CancelForwardRequest(address user,address to,uint256 orderId,uint64 deadline,uint256 nonce)");

    bytes32 private constant CANCEL_FORWARDREQUEST_TYPEHASH = keccak256(CANCEL_FORWARDREQUEST_TYPE);

    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
    }

    struct OrderForwardRequest {
        address user;
        address to;
        IOrderProcessor.Order order;
        uint256 deadline;
        uint256 nonce;
    }

    struct CancelForwardRequest {
        address user;
        address to;
        uint256 orderId;
        uint256 deadline;
        uint256 nonce;
    }

    function _hashOrderForwardRequest(OrderForwardRequest calldata metaTx) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_FORWARDREQUEST_TYPEHASH,
                metaTx.user,
                metaTx.to,
                keccak256(
                    abi.encodePacked(
                        ORDER_TYPEHASH,
                        metaTx.order.recipient,
                        metaTx.order.assetToken,
                        metaTx.order.paymentToken,
                        metaTx.order.sell,
                        metaTx.order.orderType,
                        metaTx.order.assetTokenQuantity,
                        metaTx.order.paymentTokenQuantity,
                        metaTx.order.price,
                        metaTx.order.tif,
                        metaTx.order.splitRecipient,
                        metaTx.order.splitAmount
                    )
                ),
                metaTx.deadline,
                metaTx.nonce
            )
        );
    }

    function _hashCancelRequest(CancelForwardRequest calldata metaTx) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CANCEL_FORWARDREQUEST_TYPEHASH, metaTx.user, metaTx.to, metaTx.orderId, metaTx.deadline, metaTx.nonce
            )
        );
    }

    function getOrderHashToSign(OrderForwardRequest calldata metaTx) public view returns (bytes32) {
        // This uses EIP712's _hashTypedDataV4 which conforms to the standard
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, _hashOrderForwardRequest(metaTx)));
    }

    function getCancelHashToSign(CancelForwardRequest calldata metaTx) public view returns (bytes32) {
        // This uses EIP712's _hashTypedDataV4 which conforms to the standard
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, _hashCancelRequest(metaTx)));
    }
}
