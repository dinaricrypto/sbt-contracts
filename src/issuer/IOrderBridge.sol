// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @notice Bridge interface managing orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/IOrderBridge.sol)
interface IOrderBridge {
    enum OrderType {
        MARKET,
        LIMIT
    }

    enum TIF {
        DAY, // Open until end of day
        GTC, // Good until cancelled
        IOC, // Immediate or cancel
        FOK // Fill or kill
    }

    // Emitted order data for off-chain order fulfillment
    struct Order {
        // Recipient of order fills
        address recipient;
        // Bridged asset token
        address assetToken;
        // Payment token
        address paymentToken;
        // Buy or sell
        bool sell;
        // Market or limit
        OrderType orderType;
        // Amount of asset token to be used for fills
        uint256 assetTokenQuantity;
        // Amount of payment token to be used for fills
        uint256 paymentTokenQuantity;
        // Price for limit orders
        uint256 price;
        // Time in force
        TIF tif;
        // Fee held in escrow for order
        uint256 fee;
    }

    event OrderRequested(bytes32 indexed id, address indexed recipient, Order order, bytes32 salt);
    event OrderFill(bytes32 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount);
    event OrderFulfilled(bytes32 indexed id, address indexed recipient);
    event CancelRequested(bytes32 indexed id, address indexed recipient);
    event OrderCancelled(bytes32 indexed id, address indexed recipient, string reason);

    /// @notice Total number of open orders
    function numOpenOrders() external view returns (uint256);

    /// @notice Generate Order ID deterministically from order and salt
    /// @param order Order to get ID for
    /// @param salt Salt used to generate unique order ID
    function getOrderId(Order calldata order, bytes32 salt) external view returns (bytes32);

    /// @notice Active status of order
    /// @param id Order ID to check
    function isOrderActive(bytes32 id) external view returns (bool);

    /// @notice Get remaining order quantity to fill
    /// @param id Order ID to check
    function getRemainingOrder(bytes32 id) external view returns (uint256);

    /// @notice Get total received for order
    /// @param id Order ID to check
    function getTotalReceived(bytes32 id) external view returns (uint256);
}
