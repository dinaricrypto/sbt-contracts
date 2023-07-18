// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

/// @notice Interface for contracts processing orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/issuer/IOrderBridge.sol)
/// This interface provides a standard Order type and order lifecycle events
/// Orders are requested on-chain, processed off-chain, then fulfillment is submitted for on-chain settlement
/// Bridge operators have a consistent interface for processing orders and submitting fulfillment
interface IOrderBridge {
    /// ------------------ Types ------------------ ///

    // Market or limit order
    enum OrderType {
        MARKET,
        LIMIT
    }

    // Time in force
    enum TIF
    // Good until end of day
    {
        DAY,
        // Good until cancelled
        GTC,
        // Immediate or cancel
        IOC,
        // Fill or kill
        FOK
    }

    // Emitted order data for off-chain order fulfillment
    struct Order {
        // Recipient of order fills
        address recipient;
        // Order index
        uint256 index;
        // Raw amount initially deposited for order
        uint256 quantityIn;
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
    }

    /// @dev Fully specifies order details and salt used to generate order ID
    event OrderRequested(address indexed recipient, uint256 indexed index, Order order);
    /// @dev Emitted for each fill
    event OrderFill(address indexed recipient, uint256 indexed index, uint256 fillAmount, uint256 receivedAmount);
    /// @dev Emitted when order is completely filled, terminal
    event OrderFulfilled(address indexed recipient, uint256 indexed index);
    /// @dev Emitted when order cancellation is requested
    event CancelRequested(address indexed recipient, uint256 indexed index);
    /// @dev Emitted when order is cancelled, terminal
    event OrderCancelled(address indexed recipient, uint256 indexed index, string reason);

    /// ------------------ Getters ------------------ ///

    /// @notice Total number of open orders
    function numOpenOrders() external view returns (uint256);

    /// @notice Get order ID from order recipient and index
    /// @param recipient Recipient of order fills
    /// @param index Recipient order index
    /// @dev Order ID is used as key to store order state
    function getOrderId(address recipient, uint256 index) external pure returns (bytes32);

    /// @notice Active status of order
    /// @param id Order ID
    function isOrderActive(bytes32 id) external view returns (bool);

    /// @notice Get remaining order quantity to fill
    /// @param id Order ID
    function getRemainingOrder(bytes32 id) external view returns (uint256);

    /// @notice Get total received for order
    /// @param id Order ID
    function getTotalReceived(bytes32 id) external view returns (uint256);
}
