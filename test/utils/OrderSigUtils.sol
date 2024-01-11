// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "../../src/orders/OrderProcessor.sol";

contract OrderSigUtils {
    OrderProcessor private immutable orderProcessor;

    bytes32 private constant ORDER_TYPEHASH = keccak256(
        "Order(address recipient,address assetToken,address paymentToken,bool sell,uint8 orderType,uint256 assetTokenQuantity,uint256 paymentTokenQuantity,uint256 price,uint8 tif,bool escrowUnlocked)"
    );

    bytes32 private constant ORDER_REQUEST_TYPEHASH =
        keccak256("OrderRequest(bytes32 orderHash,uint256 deadline,uint256 nonce)");

    constructor(OrderProcessor _orderProcessor) {
        orderProcessor = _orderProcessor;
    }

    function getOrderRequestHashToSign(IOrderProcessor.Order calldata order, uint256 deadline, uint256 nonce)
        public
        view
        returns (bytes32)
    {
        // This uses EIP712's _hashTypedDataV4 which conforms to the standard
        return keccak256(
            abi.encodePacked(
                "\x19\x01", orderProcessor.DOMAIN_SEPARATOR(), orderProcessor.hashOrderRequest(order, deadline, nonce)
            )
        );
    }
}
