// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SafeERC20, IERC20, IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import "./Issuer.sol";
import "../IMintBurn.sol";

/// @notice Contract managing swap market orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/SwapOrderIssuer.sol)
contract SwapOrderIssuer is Issuer {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Permit;
    // This contract handles the submission and fulfillment of orders

    // 1. Order submitted and payment/asset escrowed
    // 2. Order fulfilled, escrow claimed, assets minted/burned

    struct SwapOrder {
        address recipient;
        address assetToken;
        address paymentToken;
        bool sell;
        uint256 quantityIn;
    }

    struct OrderState {
        uint256 remainingOrder;
        uint256 remainingFees;
        uint256 totalReceived;
    }

    // uint256 flatFee;
    // uint256 percentageFee;

    error ZeroValue();
    error NotRecipient();
    error OrderNotFound();
    error DuplicateOrder();
    error FillTooLarge();
    error OrderTooSmall();

    bytes32 private constant SWAPORDER_TYPE_HASH = keccak256(
        "SwapOrder(bytes32 salt,address recipient,address assetToken,address paymentToken,bool sell,uint256 quantityIn"
    );

    /// @dev unfilled orders
    mapping(bytes32 => OrderState) private _orders;

    function getOrderIdFromSwapOrder(SwapOrder memory order, bytes32 salt) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                SWAPORDER_TYPE_HASH,
                salt,
                order.recipient,
                order.assetToken,
                order.paymentToken,
                order.sell,
                order.quantityIn
            )
        );
    }

    function getOrderId(Order calldata order, bytes32 salt) external pure returns (bytes32) {
        return getOrderIdFromSwapOrder(getSwapOrderForOrder(order), salt);
    }

    function getSwapOrderForOrder(Order calldata order) public pure returns (SwapOrder memory) {
        return SwapOrder({
            recipient: order.recipient,
            assetToken: order.assetToken,
            paymentToken: order.paymentToken,
            sell: order.sell,
            quantityIn: (order.sell ? order.assetTokenQuantity : order.paymentTokenQuantity) + order.fee
        });
    }

    function isOrderActive(bytes32 id) external view returns (bool) {
        return _orders[id].remainingOrder > 0;
    }

    function getRemainingOrder(bytes32 id) external view returns (uint256) {
        return _orders[id].remainingOrder;
    }

    function getTotalReceived(bytes32 id) external view returns (uint256) {
        return _orders[id].totalReceived;
    }

    function requestOrder(SwapOrder calldata order, bytes32 salt) public {
        _requestOrderAccounting(order, salt);

        // Escrow
        IERC20(order.sell ? order.assetToken : order.paymentToken).safeTransferFrom(
            msg.sender, address(this), order.quantityIn
        );
    }

    function requestOrderWithPermit(
        SwapOrder calldata order,
        bytes32 salt,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _requestOrderAccounting(order, salt);

        // Escrow
        address tokenIn = order.sell ? order.assetToken : order.paymentToken;
        IERC20Permit(tokenIn).safePermit(msg.sender, address(this), value, deadline, v, r, s);
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), order.quantityIn);
    }

    function fillOrder(SwapOrder calldata order, bytes32 salt, uint256 spendAmount, uint256 receivedAmount)
        external
        onlyRole(OPERATOR_ROLE)
    {
        if (spendAmount == 0) revert ZeroValue();
        bytes32 orderId = getOrderIdFromSwapOrder(order, salt);
        OrderState memory orderState = _orders[orderId];
        if (orderState.remainingOrder == 0) revert OrderNotFound();
        if (spendAmount > orderState.remainingOrder) revert FillTooLarge();

        emit OrderFill(orderId, order.recipient, spendAmount, receivedAmount);
        uint256 remainingUnspent = orderState.remainingOrder - spendAmount;
        uint256 collection = 0;
        if (remainingUnspent == 0) {
            delete _orders[orderId];
            numOpenOrders--;
            collection = orderState.remainingFees;
            emit OrderFulfilled(orderId, order.recipient);
        } else {
            _orders[orderId].remainingOrder = remainingUnspent;
            _orders[orderId].totalReceived = orderState.totalReceived + receivedAmount;
            if (orderState.remainingFees > 0) {
                collection = PrbMath.mulDiv(orderState.remainingFees, spendAmount, orderState.remainingOrder);
                _orders[orderId].remainingFees = orderState.remainingFees - collection;
            }
        }

        address tokenIn = order.sell ? order.assetToken : order.paymentToken;
        // Collect fees from tokenIn
        if (collection > 0) {
            IERC20(tokenIn).safeTransfer(treasury, collection);
        }
        // Mint/Burn
        if (order.sell) {
            // Forward proceeds
            IERC20(order.paymentToken).safeTransferFrom(msg.sender, order.recipient, receivedAmount);
            IMintBurn(order.assetToken).burn(spendAmount);
        } else {
            // Claim payment
            IERC20(tokenIn).safeTransfer(msg.sender, spendAmount);
            IMintBurn(order.assetToken).mint(order.recipient, receivedAmount);
        }
    }

    function requestCancel(SwapOrder calldata order, bytes32 salt) external {
        if (order.recipient != msg.sender) revert NotRecipient();
        bytes32 orderId = getOrderIdFromSwapOrder(order, salt);
        uint256 remainingOrder = _orders[orderId].remainingOrder;
        if (remainingOrder == 0) revert OrderNotFound();

        emit CancelRequested(orderId, order.recipient);
    }

    function cancelOrder(SwapOrder calldata order, bytes32 salt, string calldata reason)
        external
        onlyRole(OPERATOR_ROLE)
    {
        bytes32 orderId = getOrderIdFromSwapOrder(order, salt);
        OrderState memory orderState = _orders[orderId];
        if (orderState.remainingOrder == 0) revert OrderNotFound();

        delete _orders[orderId];
        numOpenOrders--;
        emit OrderCancelled(orderId, order.recipient, reason);

        // Return Escrow
        IERC20(order.sell ? order.assetToken : order.paymentToken).safeTransfer(
            order.recipient, orderState.remainingOrder + orderState.remainingFees
        );
    }

    function _requestOrderAccounting(SwapOrder calldata order, bytes32 salt) internal whenOrdersNotPaused {
        if (order.quantityIn == 0) revert ZeroValue();
        _checkRole(ASSETTOKEN_ROLE, order.assetToken);
        _checkRole(PAYMENTTOKEN_ROLE, order.paymentToken);
        bytes32 orderId = getOrderIdFromSwapOrder(order, salt);
        if (_orders[orderId].remainingOrder > 0) revert DuplicateOrder();

        uint256 collection = getFeesForOrder(order.assetToken, order.quantityIn);
        if (collection >= order.quantityIn) revert OrderTooSmall();

        uint256 orderAmount = order.quantityIn - collection;
        _orders[orderId] = OrderState({remainingOrder: orderAmount, remainingFees: collection, totalReceived: 0});
        numOpenOrders++;
        Order memory bridgeOrderData = Order({
            recipient: order.recipient,
            assetToken: order.assetToken,
            paymentToken: order.paymentToken,
            sell: order.sell,
            orderType: OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 0,
            price: 0,
            tif: TIF.DAY,
            fee: collection
        });
        if (order.sell) {
            bridgeOrderData.assetTokenQuantity = orderAmount;
        } else {
            bridgeOrderData.paymentTokenQuantity = orderAmount;
        }
        emit OrderRequested(orderId, order.recipient, bridgeOrderData, salt);
    }
}
