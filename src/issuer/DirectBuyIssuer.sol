// SPDX-License-Identifier: UNLICENSED
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

    event OrderTaken(bytes32 indexed orderId, address indexed recipient, uint256 amount);
    event EscrowReturned(bytes32 indexed orderId, address indexed recipient, uint256 amount);

    mapping(bytes32 => uint256) public getOrderEscrow;

    function takeEscrow(OrderRequest calldata order, bytes32 salt, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        if (amount == 0) revert ZeroValue();
        bytes32 orderId = getOrderIdFromOrderRequest(order, salt);
        uint256 escrow = getOrderEscrow[orderId];
        if (amount > escrow) revert AmountTooLarge();

        getOrderEscrow[orderId] = escrow - amount;
        emit OrderTaken(orderId, order.recipient, amount);

        // Claim payment
        IERC20(order.paymentToken).safeTransfer(msg.sender, amount);
    }

    function returnEscrow(OrderRequest calldata order, bytes32 salt, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        if (amount == 0) revert ZeroValue();
        bytes32 orderId = getOrderIdFromOrderRequest(order, salt);
        uint256 remainingOrder = _orders[orderId].remainingOrder;
        uint256 escrow = getOrderEscrow[orderId];
        // Can only return unused amount
        if (escrow + amount > remainingOrder) revert AmountTooLarge();

        getOrderEscrow[orderId] = escrow + amount;
        emit EscrowReturned(orderId, order.recipient, amount);

        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), amount);
    }

    function _requestOrderAccounting(OrderRequest calldata order, bytes32 salt, bytes32 orderId)
        internal
        virtual
        override
    {
        super._requestOrderAccounting(order, salt, orderId);
        getOrderEscrow[orderId] = _orders[orderId].remainingOrder;
    }

    function _fillOrderAccounting(
        OrderRequest calldata order,
        bytes32 orderId,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256
    ) internal virtual override {
        uint256 escrow = getOrderEscrow[orderId];
        if (orderState.remainingOrder - fillAmount < escrow) revert AmountTooLarge();

        super._fillOrderAccounting(order, orderId, orderState, fillAmount, receivedAmount, 0);
    }

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
