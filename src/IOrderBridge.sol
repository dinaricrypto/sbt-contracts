// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/// @notice Bridge interface managing orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/IOrderBridge.sol)
interface IOrderBridge {
    enum OrderType {
        MARKET,
        LIMIT
    }

    enum TIF {
        DAY,
        GTC,
        IOC,
        FOK
    }

    struct Order {
        address recipient;
        address assetToken;
        address paymentToken;
        bool sell;
        OrderType orderType;
        uint256 assetTokenQuantity;
        uint256 paymentTokenQuantity;
        uint256 price;
        // Time in force
        TIF tif;
    }

    event OrderRequested(bytes32 indexed id, address indexed recipient, Order order, bytes32 salt);
    event OrderFill(bytes32 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount);
    event OrderFulfilled(bytes32 indexed id, address indexed recipient);
    event CancelRequested(bytes32 indexed id, address indexed recipient);
    event OrderCancelled(bytes32 indexed id, address indexed recipient, string reason);

    function isOrderActive(bytes32 id) external view returns (bool);

    function numOpenOrders() external view returns (uint256);
}
