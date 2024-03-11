// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../src/orders/OrderProcessor.sol";

contract OrderSigUtils {
    OrderProcessor private immutable orderProcessor;

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
