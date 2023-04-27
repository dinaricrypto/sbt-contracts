// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solady/auth/OwnableRoles.sol";
import "solady/utils/SafeTransferLib.sol";
import "./IMintBurn.sol";

/// @notice Bridge interface managing swaps for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/Bridge.sol)
contract Bridge is OwnableRoles {
    // This contract handles the submission and fulfillment of orders
    // submit by sig - forwarder/gsn support?
    // TODO: upgradeable, pausable
    // TODO: fees
    // TODO: liquidity pools for cross-chain swaps
    // TODO: is there a more secure way than holding all escrow here?
    // TODO: support multiple identical orders from the same account, prevent double spend orders - check for collisions
    // TODO: add proof of fulfillment?
    // TODO: should we allow beneficiary != submit msg.sender?

    // 1. Order submitted and payment escrowed
    // 2. Order fulfilled and escrow claimed
    // 2a. If order failed, escrow released
    // Orders are eligible for cancelation if fulfillment within maxSlippage cannot be achieved before expiration

    struct OrderInfo {
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

    event PaymentTokenEnabled(address indexed token, bool enabled);
    event PurchaseSubmitted(bytes32 indexed orderId, address indexed user, OrderInfo orderInfo);
    event RedemptionSubmitted(bytes32 indexed orderId, address indexed user, OrderInfo orderInfo);
    event PurchaseFulfilled(bytes32 indexed orderId, address indexed user, uint256 amount);
    event RedemptionFulfilled(bytes32 indexed orderId, address indexed user, uint256 amount);

    // keccak256(OrderInfo(address user,address assetToken,address paymentToken,uint128 amount,uint128 price))
    bytes32 public constant ORDERINFO_TYPE_HASH = 0x2596959a062a89c4860f6e081086d24582adcdaf7d5988da87cbb652a577d20f;

    /// @dev accepted payment tokens for this issuer
    mapping(address => bool) public paymentTokenEnabled;

    /// @dev unfulfilled orders
    mapping(bytes32 => bool) private _purchases;
    mapping(bytes32 => bool) private _redemptions;

    constructor() {
        _initializeOwner(msg.sender);
    }

    function operatorRole() external pure returns (uint256) {
        return _ROLE_1;
    }

    function isPurchaseActive(bytes32 orderId) external view returns (bool) {
        return _purchases[orderId];
    }

    function isRedemptionActive(bytes32 orderId) external view returns (bool) {
        return _redemptions[orderId];
    }

    function hashOrderInfo(OrderInfo memory orderInfo) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDERINFO_TYPE_HASH,
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

        // Emit the data, store the hash
        bytes32 orderId = hashOrderInfo(order);
        _purchases[orderId] = true;
        emit PurchaseSubmitted(orderId, order.user, order);

        // Move payment tokens
        uint256 paymentAmount = uint256(order.amount) * order.price;
        SafeTransferLib.safeTransferFrom(order.paymentToken, msg.sender, address(this), paymentAmount);
    }

    function submitRedemption(OrderInfo calldata order) external {
        if (order.user != msg.sender) revert NoProxyOrders();
        if (order.amount == 0 || order.price == 0) revert ZeroValue();
        if (!paymentTokenEnabled[order.paymentToken]) revert UnsupportedPaymentToken();

        // Emit the data, store the hash
        bytes32 orderId = hashOrderInfo(order);
        _redemptions[orderId] = true;
        emit RedemptionSubmitted(orderId, order.user, order);

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

    function fulfillRedemption(OrderInfo calldata order, uint256 proceeds) external onlyRoles(_ROLE_1) {
        bytes32 orderId = hashOrderInfo(order);
        if (!_redemptions[orderId]) revert OrderNotFound();

        delete _redemptions[orderId];
        emit RedemptionFulfilled(orderId, order.user, proceeds);

        // Forward payment
        SafeTransferLib.safeTransferFrom(order.paymentToken, msg.sender, order.user, proceeds);
        // Burn
        IMintBurn(order.assetToken).burn(order.amount);
    }
}
