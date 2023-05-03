// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/// @notice Bridge interface managing swaps for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/IVaultBridge.sol)
interface IVaultBridge {
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
        address user;
        address assetToken;
        address paymentToken;
        bool sell;
        OrderType orderType;
        uint256 assetTokenQuantity;
        uint256 paymentTokenQuantity;
        // Time in force
        TIF tif;
    }

    event OrderRequested(bytes32 indexed id, address indexed user, Order order, bytes32 salt);
    event OrderFill(bytes32 indexed id, address indexed user, uint256 fillAmount, uint256 proceeds);
    event OrderFulfilled(bytes32 indexed id, address indexed user, uint256 filledAmount);
    event CancelRequested(bytes32 indexed id, address indexed user);
    event OrderCancelled(bytes32 indexed id, address indexed user, string reason);

    function getOrderId(Order calldata order, bytes32 salt) external view returns (bytes32);

    function isOrderActive(bytes32 id) external view returns (bool);

    function getUnfilledAmount(bytes32 id) external view returns (uint256);

    function requestOrder(Order calldata order, bytes32 salt) external;

    function fillOrder(Order calldata order, bytes32 salt, uint256 filledAmount, uint256 resultAmount) external;

    function requestCancel(Order calldata order, bytes32 salt) external;

    function cancelOrder(Order calldata order, bytes32 salt, string calldata reason) external;
}
