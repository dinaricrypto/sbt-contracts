// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BuyOrderIssuer.sol";
import "../IMintBurn.sol";

/// @notice Contract managing direct market buy swap orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/issuer/DirectBuyIssuer.sol)
contract DirectBuyIssuer is BuyOrderIssuer {
    using SafeERC20 for IERC20;
    // This contract handles the submission and fulfillment of orders

    // 1. Order submitted and payment escrowed
    // 2. Payment taken
    // 3. Order fulfilled, fees claimed, assets minted

    error UnreturnedEscrow();

    event EscrowTaken(bytes32 indexed orderId, address indexed recipient, uint256 amount);
    event EscrowReturned(bytes32 indexed orderId, address indexed recipient, uint256 amount);

    // orderId => escrow
    mapping(bytes32 => uint256) public getOrderEscrow;

    /// @notice Take escrowed payment for an order
    /// @param orderRequest Order request
    /// @param salt Salt used to generate unique order ID
    /// @param amount Amount of escrowed payment token to take
    /// @dev Only callable by operator
    function takeEscrow(OrderRequest calldata orderRequest, bytes32 salt, uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
    {
        if (amount == 0) revert ZeroValue();
        bytes32 orderId = getOrderIdFromOrderRequest(orderRequest, salt);
        uint256 escrow = getOrderEscrow[orderId];
        if (amount > escrow) revert AmountTooLarge();

        getOrderEscrow[orderId] = escrow - amount;
        emit EscrowTaken(orderId, orderRequest.recipient, amount);

        // Claim payment
        IERC20(orderRequest.paymentToken).safeTransfer(msg.sender, amount);
    }

    /// @notice Return unused escrowed payment for an order
    /// @param orderRequest Order request
    /// @param salt Salt used to generate unique order ID
    /// @param amount Amount of payment token to return to escrow
    /// @dev Only callable by operator
    function returnEscrow(OrderRequest calldata orderRequest, bytes32 salt, uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
    {
        if (amount == 0) revert ZeroValue();
        bytes32 orderId = getOrderIdFromOrderRequest(orderRequest, salt);
        uint256 remainingOrder = getRemainingOrder(orderId);
        uint256 escrow = getOrderEscrow[orderId];
        // Can only return unused amount
        if (escrow + amount > remainingOrder) revert AmountTooLarge();

        getOrderEscrow[orderId] = escrow + amount;
        emit EscrowReturned(orderId, orderRequest.recipient, amount);

        IERC20(orderRequest.paymentToken).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc OrderProcessor
    function _requestOrderAccounting(OrderRequest calldata orderRequest, bytes32 orderId)
        internal
        virtual
        override
        returns (Order memory order)
    {
        order = super._requestOrderAccounting(orderRequest, orderId);
        getOrderEscrow[orderId] = order.paymentTokenQuantity;
    }

    /// @inheritdoc OrderProcessor
    function _fillOrderAccounting(
        OrderRequest calldata orderRequest,
        bytes32 orderId,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256
    ) internal virtual override {
        uint256 escrow = getOrderEscrow[orderId];
        if (orderState.remainingOrder - fillAmount < escrow) revert AmountTooLarge();

        super._fillOrderAccounting(orderRequest, orderId, orderState, fillAmount, receivedAmount, 0);
    }

    /// @inheritdoc OrderProcessor
    function _cancelOrderAccounting(OrderRequest calldata order, bytes32 orderId, OrderState memory orderState)
        internal
        virtual
        override
    {
        uint256 escrow = getOrderEscrow[orderId];
        if (orderState.remainingOrder != escrow) revert UnreturnedEscrow();

        super._cancelOrderAccounting(order, orderId, orderState);
    }
}
