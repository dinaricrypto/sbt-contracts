// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {BuyOrderIssuer, OrderProcessor} from "./BuyOrderIssuer.sol";
import {IMintBurn} from "../IMintBurn.sol";

/// @notice Contract managing market purchase orders for bridged assets with direct payment
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/issuer/DirectBuyIssuer.sol)
/// This order processor emits market orders to buy the underlying asset that are good until cancelled
/// Fees are calculated upfront and held back from the order amount
/// The payment is taken by the operator before the order is filled
/// The operator can return unused payment to the user
/// The operator cannot cancel the order until payment is returned or the order is filled
/// Implicitly assumes that asset tokens are BridgedERC20 and can be minted
/// Order lifecycle (fulfillment):
///   1. User requests an order (requestOrder)
///   2. Operator takes escrowed payment (takeEscrow)
///   3. [Optional] Operator partially fills the order (fillOrder)
///   4. Operator completely fulfills the order (fillOrder)
/// Order lifecycle (cancellation):
///   1. User requests an order (requestOrder)
///   2. Operator takes escrowed payment (takeEscrow)
///   3. [Optional] Operator partially fills the order (fillOrder)
///   4. [Optional] User requests cancellation (requestCancel)
///   5. Operator returns unused payment to contract (returnEscrow)
///   6. Operator cancels the order (cancelOrder)
contract DirectBuyIssuer is BuyOrderIssuer {
    using SafeERC20 for IERC20;

    /// ------------------ Types ------------------ ///

    /// @dev Escrowed payment has been taken
    error UnreturnedEscrow();

    /// @dev Emitted when `amount` of escrowed payment is taken for `orderId`
    event EscrowTaken(bytes32 indexed orderId, address indexed recipient, uint256 amount);
    /// @dev Emitted when `amount` of escrowed payment is returned for `orderId`
    event EscrowReturned(bytes32 indexed orderId, address indexed recipient, uint256 amount);

    /// ------------------ State ------------------ ///

    /// @dev orderId => escrow
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
        // Unused amount = remaining order - remaining escrow
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
        uint256 receivedAmount
    ) internal virtual override {
        // Can't fill more than payment previously taken from escrow
        uint256 escrow = getOrderEscrow[orderId];
        if (fillAmount > orderState.remainingOrder - escrow) revert AmountTooLarge();

        // Buy order accounting
        _fillBuyOrder(orderRequest, orderId, orderState, fillAmount, receivedAmount);
    }

    /// @inheritdoc OrderProcessor
    function _cancelOrderAccounting(OrderRequest calldata order, bytes32 orderId, OrderState memory orderState)
        internal
        virtual
        override
    {
        // Prohibit cancel if escrowed payment has been taken and not returned or filled
        uint256 escrow = getOrderEscrow[orderId];
        if (orderState.remainingOrder != escrow) revert UnreturnedEscrow();

        // Standard buy order accounting
        super._cancelOrderAccounting(order, orderId, orderState);
    }
}
