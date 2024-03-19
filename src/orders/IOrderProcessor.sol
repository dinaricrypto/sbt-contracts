// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

/// @notice Interface for contracts processing orders for dShares
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/orders/IOrderProcessor.sol)
/// This interface provides a standard Order type and order lifecycle events
/// Orders are requested on-chain, processed off-chain, then fulfillment is submitted for on-chain settlement
interface IOrderProcessor {
    /// ------------------ Types ------------------ ///

    // Market or limit order
    enum OrderType {
        MARKET,
        LIMIT
    }

    // Time in force
    enum TIF {
        // Good until end of day
        DAY,
        // Good until cancelled
        GTC,
        // Immediate or cancel
        IOC,
        // Fill or kill
        FOK
    }

    // Order status enum
    enum OrderStatus {
        // Order has never existed
        NONE,
        // Order is active
        ACTIVE,
        // Order is completely filled
        FULFILLED,
        // Order is cancelled
        CANCELLED
    }

    struct Order {
        // Salt added to order hash
        uint256 salt;
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
    }

    struct OrderRequest {
        // Unique ID and hash of order data used to validate order details stored offchain
        uint256 id;
        // Signature expiration timestamp
        uint256 deadline;
    }

    struct Signature {
        // Signature expiration timestamp
        uint256 deadline;
        // Signature bytes (r, s, v)
        bytes signature;
    }

    /// @dev Emitted order details and order ID for each order
    event OrderCreated(uint256 indexed id, address indexed requester, Order order);
    /// @dev Emitted for each fill
    event OrderFill(
        uint256 indexed id,
        address indexed paymentToken,
        address indexed assetToken,
        address requester,
        uint256 paymentAmount,
        uint256 assetAmount,
        uint256 fees,
        bool sell
    );
    /// @dev Emitted when order is completely filled, terminal
    event OrderFulfilled(uint256 indexed id, address indexed requester);
    /// @dev Emitted when order cancellation is requested
    event CancelRequested(uint256 indexed id, address indexed requester);
    /// @dev Emitted when order is cancelled, terminal
    event OrderCancelled(uint256 indexed id, address indexed requester, string reason);

    /// ------------------ Getters ------------------ ///

    /// @notice Hash order data for validation and create unique order ID
    /// @param order Order data
    /// @dev EIP-712 typed data hash of order
    function hashOrder(Order calldata order) external pure returns (uint256);

    /// @notice Status of a given order
    /// @param id Order ID
    function getOrderStatus(uint256 id) external view returns (OrderStatus);

    /// @notice Get remaining order quantity to fill
    /// @param id Order ID
    function getUnfilledAmount(uint256 id) external view returns (uint256);

    /// @notice This function retrieves the number of decimal places configured for a given token
    /// @param token The address of the token for which the number of decimal places is fetched
    /// @return Returns the number of decimal places set for the specified token
    function maxOrderDecimals(address token) external view returns (int8);

    /// @notice Get fee rates for an order
    /// @param sell Sell order
    /// @param paymentToken Payment token for order
    /// @return flatFee Flat fee for order
    /// @return percentageFeeRate Percentage fee rate for order
    function getStandardFeeRates(bool sell, address paymentToken) external view returns (uint256, uint24);

    /// @notice Check if an account is locked from transferring tokens
    /// @param token Token to check
    /// @param account Account to check
    /// @dev Only used for payment tokens
    function isTransferLocked(address token, address account) external view returns (bool);

    /// ------------------ Actions ------------------ ///

    /// @notice Lock tokens and initialize signed order
    /// @param order Order request to initialize
    /// @param signature Signature for order
    /// @return id Order id
    /// @dev Only callable by operator
    function createOrderWithSignature(Order calldata order, Signature calldata signature) external returns (uint256);

    /// @notice Request an order
    /// @param order Order request to submit
    /// @return id Order id
    /// @dev Emits OrderCreated event to be sent to fulfillment service (operator)
    function requestOrder(Order calldata order) external returns (uint256);

    /// @notice Fill an order
    /// @param id order id
    /// @param order Order request to fill
    /// @param fillAmount Amount of order token to fill
    /// @param receivedAmount Amount of received token
    /// @dev Only callable by operator
    function fillOrder(uint256 id, Order calldata order, uint256 fillAmount, uint256 receivedAmount, uint256 fees)
        external;

    /// @notice Request to cancel an order
    /// @param id Order id
    /// @dev Only callable by initial order requester
    /// @dev Emits CancelRequested event to be sent to fulfillment service (operator)
    function requestCancel(uint256 id) external;

    /// @notice Cancel an order
    /// @param order id
    /// @param order Order request to cancel
    /// @param reason Reason for cancellation
    /// @dev Only callable by operator
    function cancelOrder(uint256 id, Order calldata order, string calldata reason) external;
}
