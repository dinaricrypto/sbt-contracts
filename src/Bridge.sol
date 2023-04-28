// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solady/auth/OwnableRoles.sol";
import "solady/utils/SafeTransferLib.sol";
import "./IMintBurn.sol";

/// @notice Bridge interface managing swaps for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/Bridge.sol)
contract Bridge is OwnableRoles {
    // This contract handles the submission and fulfillment of orders
    // TODO: submit by sig - forwarder/gsn support?
    // TODO: upgradeable, pausable
    // TODO: fees
    // TODO: liquidity pools for cross-chain swaps
    // TODO: add proof of fulfillment?
    // TODO: should we allow beneficiary != submit msg.sender?
    // TODO: cancel orders

    // 1. Order submitted and payment/asset escrowed
    // 2. Order fulfilled, escrow claimed, assets minted/burned

    struct OrderInfo {
        bytes32 salt;
        address user;
        address assetToken;
        address paymentToken;
        uint128 amount;
        uint128 price;
    }

    error ZeroValue();
    error UnsupportedPaymentToken();
    error NoProxyOrders();
    error OrderNotFound();
    error DuplicateOrder();

    event PaymentTokenEnabled(address indexed token, bool enabled);
    event PurchaseSubmitted(bytes32 indexed orderId, address indexed user, OrderInfo orderInfo);
    event SaleSubmitted(bytes32 indexed orderId, address indexed user, OrderInfo orderInfo);
    event PurchaseFulfilled(bytes32 indexed orderId, address indexed user, uint256 amount);
    event SaleFulfilled(bytes32 indexed orderId, address indexed user, uint256 amount);

    // keccak256(OrderInfo(bytes32 salt,address user,address assetToken,address paymentToken,uint128 amount,uint128 price))
    bytes32 public constant ORDERINFO_TYPE_HASH = 0x48b55fd842c35498e68cc0663faa85682a260093cebf3a270227d3cad69d1a69;

    /// @dev accepted payment tokens for this issuer
    mapping(address => bool) public paymentTokenEnabled;

    /// @dev unfulfilled orders
    mapping(bytes32 => bool) private _purchases;
    mapping(bytes32 => bool) private _sales;

    constructor() {
        _initializeOwner(msg.sender);
    }

    function operatorRole() external pure returns (uint256) {
        return _ROLE_1;
    }

    function isPurchaseActive(bytes32 orderId) external view returns (bool) {
        return _purchases[orderId];
    }

    function isSaleActive(bytes32 orderId) external view returns (bool) {
        return _sales[orderId];
    }

    function hashOrderInfo(OrderInfo memory orderInfo) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDERINFO_TYPE_HASH,
                orderInfo.salt,
                orderInfo.user,
                orderInfo.assetToken,
                orderInfo.paymentToken,
                orderInfo.amount,
                orderInfo.price
            )
        );
    }

    function setPaymentTokenEnabled(address token, bool enabled) external onlyOwner {
        paymentTokenEnabled[token] = enabled;
        emit PaymentTokenEnabled(token, enabled);
    }

    function submitPurchase(OrderInfo calldata order) external {
        if (order.user != msg.sender) revert NoProxyOrders();
        if (order.amount == 0 || order.price == 0) revert ZeroValue();
        if (!paymentTokenEnabled[order.paymentToken]) revert UnsupportedPaymentToken();
        bytes32 orderId = hashOrderInfo(order);
        if (_purchases[orderId]) revert DuplicateOrder();

        // Emit the data, store the hash
        _purchases[orderId] = true;
        emit PurchaseSubmitted(orderId, order.user, order);

        // Move payment tokens
        uint256 paymentAmount = uint256(order.amount) * order.price;
        SafeTransferLib.safeTransferFrom(order.paymentToken, msg.sender, address(this), paymentAmount);
    }

    function submitSale(OrderInfo calldata order) external {
        if (order.user != msg.sender) revert NoProxyOrders();
        if (order.amount == 0 || order.price == 0) revert ZeroValue();
        if (!paymentTokenEnabled[order.paymentToken]) revert UnsupportedPaymentToken();
        bytes32 orderId = hashOrderInfo(order);
        if (_sales[orderId]) revert DuplicateOrder();

        // Emit the data, store the hash
        _sales[orderId] = true;
        emit SaleSubmitted(orderId, order.user, order);

        // Move asset tokens
        SafeTransferLib.safeTransferFrom(order.assetToken, msg.sender, address(this), order.amount);
    }

    function fulfillPurchase(OrderInfo calldata order, uint256 purchasedAmount) external onlyRoles(_ROLE_1) {
        bytes32 orderId = hashOrderInfo(order);
        if (!_purchases[orderId]) revert OrderNotFound();

        delete _purchases[orderId];
        emit PurchaseFulfilled(orderId, order.user, purchasedAmount);

        // Mint
        IMintBurn(order.assetToken).mint(order.user, purchasedAmount);
        // Claim payment
        uint256 paymentAmount = uint256(order.amount) * order.price;
        SafeTransferLib.safeTransfer(order.paymentToken, msg.sender, paymentAmount);
    }

    function fulfillSale(OrderInfo calldata order, uint256 proceeds) external onlyRoles(_ROLE_1) {
        bytes32 orderId = hashOrderInfo(order);
        if (!_sales[orderId]) revert OrderNotFound();

        delete _sales[orderId];
        emit SaleFulfilled(orderId, order.user, proceeds);

        // Forward payment
        SafeTransferLib.safeTransferFrom(order.paymentToken, msg.sender, order.user, proceeds);
        // Burn
        IMintBurn(order.assetToken).burn(order.amount);
    }
}
