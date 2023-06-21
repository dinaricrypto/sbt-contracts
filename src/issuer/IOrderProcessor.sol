// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IOrderProcessor {
    struct OrderRequest {
        address recipient;
        address assetToken;
        address paymentToken;
        uint256 quantityIn;
    }

    /**
     * @dev Request an order
     * @param orderRequest Order request
     * @return orderId Order ID
     */
    function requestOrder(OrderRequest calldata orderRequest) external returns (bytes32 orderId);

    /**
     * @dev Cancel an order
     * @param orderId Order ID
     */
    function requestCancel(bytes32 orderId) external;
}
