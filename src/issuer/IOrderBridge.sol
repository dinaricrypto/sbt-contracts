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

    /// @dev Fully specifies order details and salt used to generate order ID
    event OrderRequested(bytes32 indexed id, address indexed recipient, Order order, bytes32 salt);
    /// @dev Emitted for each fill
    event OrderFill(bytes32 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount);
    /// @dev Emitted when order is completely filled, terminal
    event OrderFulfilled(bytes32 indexed id, address indexed recipient);
    /// @dev Emitted when order cancellation is requested
    event CancelRequested(bytes32 indexed id, address indexed recipient);
    /// @dev Emitted when order is cancelled, terminal
    event OrderCancelled(bytes32 indexed id, address indexed recipient, string reason);

    /// ------------------ Getters ------------------ ///

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
