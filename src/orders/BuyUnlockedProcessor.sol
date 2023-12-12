// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {OrderProcessor, ITokenLockCheck} from "./OrderProcessor.sol";

/// @notice Contract managing market purchase orders for bridged assets with direct payment
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/orders/BuyUnlockedProcessor.sol)
/// This order processor emits market orders to buy the underlying asset that are good until cancelled
/// Fees are calculated upfront and held back from the order amount
/// The payment is taken by the operator before the order is filled
/// The operator can return unused payment to the user
/// The operator cannot cancel the order until payment is returned or the order is filled
/// Implicitly assumes that asset tokens are DShare and can be minted
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
contract BuyUnlockedProcessor is OrderProcessor {
    using SafeERC20 for IERC20;

    /// ------------------ Types ------------------ ///

    error NotBuyOrder();
    /// @dev Escrowed payment has been taken
    error UnreturnedEscrow();

    /// @dev Emitted when `amount` of escrowed payment is taken for order
    event EscrowTaken(uint256 indexed id, address indexed requester, uint256 amount);
    /// @dev Emitted when `amount` of escrowed payment is returned for order
    event EscrowReturned(uint256 indexed id, address indexed requester, uint256 amount);

    /// ------------------ State ------------------ ///

    struct BuyUnlockedProcessorStorage {
        // Order escrow tracking
        mapping(uint256 => uint256) _getOrderEscrow;
    }

    // keccak256(abi.encode(uint256(keccak256("dinaricrypto.storage.BuyUnlockedProcessor")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BuyUnlockedProcessorStorageLocation =
        0x9ef2e27f0661cd1c5e17cad73e47154b2655f2434621cc5680ed2d93095efa00;

    function _getBuyUnlockedProcessorStorage() private pure returns (BuyUnlockedProcessorStorage storage $) {
        assembly {
            $.slot := BuyUnlockedProcessorStorageLocation
        }
    }

    /// ------------------ Getters ------------------ ///

    /// @notice Get the amount of payment token escrowed for an order
    /// @param id order id
    function getOrderEscrow(uint256 id) external view returns (uint256) {
        BuyUnlockedProcessorStorage storage $ = _getBuyUnlockedProcessorStorage();
        return $._getOrderEscrow[id];
    }

    /// ------------------ Order Lifecycle ------------------ ///

    /// @notice Take escrowed payment for an order
    /// @param id order id
    /// @param order Order
    /// @param amount Amount of escrowed payment token to take
    /// @dev Only callable by operator
    function takeEscrow(uint256 id, Order calldata order, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        // No nonsense
        if (amount == 0) revert ZeroValue();
        // Verify order data
        bytes32 orderHash = _getOrderHash(id);
        if (orderHash != hashOrderCalldata(order)) revert InvalidOrderData();
        // Can't take more than escrowed
        BuyUnlockedProcessorStorage storage $ = _getBuyUnlockedProcessorStorage();
        uint256 escrow = $._getOrderEscrow[id];
        if (amount > escrow) revert AmountTooLarge();

        // Update escrow tracking
        $._getOrderEscrow[id] = escrow - amount;
        address requester = _getRequester(id);
        _decreaseEscrowedBalanceOf(order.paymentToken, requester, amount);
        // Notify escrow taken
        emit EscrowTaken(id, requester, amount);

        // Take escrowed payment
        IERC20(order.paymentToken).safeTransfer(msg.sender, amount);
    }

    /// @notice Return unused escrowed payment for an order
    /// @param id order id
    /// @param order Order
    /// @param amount Amount of payment token to return to escrow
    /// @dev Only callable by operator
    function returnEscrow(uint256 id, Order calldata order, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        // No nonsense
        if (amount == 0) revert ZeroValue();
        // Verify order data
        bytes32 orderHash = _getOrderHash(id);
        if (orderHash != hashOrderCalldata(order)) revert InvalidOrderData();
        // Can only return unused amount
        uint256 unfilledAmount = getUnfilledAmount(id);
        BuyUnlockedProcessorStorage storage $ = _getBuyUnlockedProcessorStorage();
        uint256 escrow = $._getOrderEscrow[id];
        // Unused amount = remaining order - remaining escrow
        if (escrow + amount > unfilledAmount) revert AmountTooLarge();

        // Update escrow tracking
        $._getOrderEscrow[id] = escrow + amount;
        address requester = _getRequester(id);
        _increaseEscrowedBalanceOf(order.paymentToken, requester, amount);
        // Notify escrow returned
        emit EscrowReturned(id, requester, amount);

        // Return payment to escrow
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc OrderProcessor
    function _requestOrderAccounting(uint256 id, Order calldata order) internal virtual override {
        // Only buy orders
        if (order.sell) revert NotBuyOrder();
        // Compile standard buy order
        super._requestOrderAccounting(id, order);
        // Initialize escrow tracking for order
        BuyUnlockedProcessorStorage storage $ = _getBuyUnlockedProcessorStorage();
        $._getOrderEscrow[id] = order.paymentTokenQuantity;
    }

    /// @inheritdoc OrderProcessor
    function _fillOrderAccounting(
        uint256 id,
        Order calldata order,
        OrderState memory orderState,
        uint256 unfilledAmount,
        uint256 fillAmount,
        uint256 receivedAmount
    ) internal virtual override returns (uint256 paymentEarned, uint256 feesEarned) {
        // Can't fill more than payment previously taken from escrow
        BuyUnlockedProcessorStorage storage $ = _getBuyUnlockedProcessorStorage();
        uint256 escrow = $._getOrderEscrow[id];
        if (fillAmount > unfilledAmount - escrow) revert AmountTooLarge();

        paymentEarned = 0;
        (, feesEarned) = super._fillOrderAccounting(id, order, orderState, unfilledAmount, fillAmount, receivedAmount);
    }

    /// @inheritdoc OrderProcessor
    function _cancelOrderAccounting(
        uint256 id,
        Order calldata order,
        OrderState memory orderState,
        uint256 unfilledAmount
    ) internal virtual override returns (uint256 refund) {
        // Prohibit cancel if escrowed payment has been taken and not returned or filled
        BuyUnlockedProcessorStorage storage $ = _getBuyUnlockedProcessorStorage();
        uint256 escrow = $._getOrderEscrow[id];
        if (unfilledAmount != escrow) revert UnreturnedEscrow();

        // Clear the escrow record
        delete $._getOrderEscrow[id];

        // Standard buy order accounting
        refund = super._cancelOrderAccounting(id, order, orderState, unfilledAmount);
    }
}
