// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/// @notice Bridge interface managing swaps for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/IVaultBridge.sol)
interface IVaultBridge {
    enum OrderType {
        MARKET,
        LIMIT
    }

    struct Order {
        address user;
        address assetToken;
        address paymentToken;
        bool sell;
        OrderType orderType;
        // For market orders, this is the source token quantity (asset for sells, payment for buys)
        // For limit orders, this is the asset token quantity
        uint256 amount;
        // Time in force
        uint64 tif;
    }

    event OrderRequested(bytes32 indexed id, address indexed user, Order order);
    event OrderFill(bytes32 indexed id, address indexed user, uint256 fillAmount);
    event OrderFulfilled(bytes32 indexed id, address indexed user, uint256 filledAmount);

    function getOrderId(Order calldata order, bytes32 salt) external view returns (bytes32);

    function isOrderActive(bytes32 id) external view returns (bool);

    function getUnfilledAmount(bytes32 id) external view returns (uint256);

    function requestOrder(Order calldata order, bytes32 salt) external;

    function fillOrder(Order calldata order, bytes32 salt, uint256 assetTokenQuantity, uint256 paymentTokenQuantity)
        external;
}
