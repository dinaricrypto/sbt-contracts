// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {BuyOrderIssuer, OrderProcessor} from "./BuyOrderIssuer.sol";
import {IMintBurn} from "../IMintBurn.sol";

/// @notice Contract managing market purchase orders for bridged assets with direct payment
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/issuer/DirectBuyIssuer.sol)
/// The escrowed payment is taken by the operator before the order is filled
/// The operator can return unused escrowed payment to the user
contract DirectBuyIssuer is BuyOrderIssuer {
    using SafeERC20 for IERC20;

    /// ------------------ Types ------------------ ///

    error UnreturnedEscrow();

    event EscrowTaken(bytes32 indexed orderId, address indexed recipient, uint256 amount);
    event EscrowReturned(bytes32 indexed orderId, address indexed recipient, uint256 amount);

    /// ------------------ State ------------------ ///

    // orderId => escrow
    mapping(bytes32 => uint256) public getOrderEscrow;

    /// ------------------ Order Lifecycle ------------------ ///

    /// @notice Take escrowed payment for an order
    /// @param orderRequest Order request
    /// @param salt Salt used to generate unique order ID
    /// @param amount Amount of escrowed payment token to take
    /// @dev Only callable by operator
    function takeEscrow(OrderRequest calldata orderRequest, bytes32 salt, uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
    {
        // No nonsense
        if (amount == 0) revert ZeroValue();
        // Can't take more than escrowed
        bytes32 orderId = getOrderIdFromOrderRequest(orderRequest, salt);
        uint256 escrow = getOrderEscrow[orderId];
        if (amount > escrow) revert AmountTooLarge();

        // Update escrow tracking
        getOrderEscrow[orderId] = escrow - amount;
        // Notify escrow taken
        emit EscrowTaken(orderId, orderRequest.recipient, amount);

        // Take escrowed payment
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
        // No nonsense
        if (amount == 0) revert ZeroValue();
        // Can only return unused amount
        bytes32 orderId = getOrderIdFromOrderRequest(orderRequest, salt);
        uint256 remainingOrder = getRemainingOrder(orderId);
        uint256 escrow = getOrderEscrow[orderId];
        if (escrow + amount > remainingOrder) revert AmountTooLarge();

        // Update escrow tracking
        getOrderEscrow[orderId] = escrow + amount;
        // Notify escrow returned
        emit EscrowReturned(orderId, orderRequest.recipient, amount);

        // Return payment to escrow
        IERC20(orderRequest.paymentToken).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc OrderProcessor
    function _requestOrderAccounting(OrderRequest calldata orderRequest, bytes32 orderId)
        internal
        virtual
        override
        returns (Order memory order)
    {
        // Compile standard buy order
        order = super._requestOrderAccounting(orderRequest, orderId);
        // Initialize escrow tracking for order
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
        // Can't fill more than payment previously taken
        uint256 escrow = getOrderEscrow[orderId];
        if (fillAmount > orderState.remainingOrder - escrow) revert AmountTooLarge();

        // Standard buy order accounting
        super._fillOrderAccounting(orderRequest, orderId, orderState, fillAmount, receivedAmount, 0);
    }

    /// @inheritdoc OrderProcessor
    function _cancelOrderAccounting(OrderRequest calldata order, bytes32 orderId, OrderState memory orderState)
        internal
        virtual
        override
    {
        // Can't cancel if escrowed payment has been taken
        uint256 escrow = getOrderEscrow[orderId];
        if (orderState.remainingOrder != escrow) revert UnreturnedEscrow();

        // Standard buy order accounting
        super._cancelOrderAccounting(order, orderId, orderState);
    }
}
