// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SafeERC20, IERC20, IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import "./Issuer.sol";
import "../IMintBurn.sol";

/// @notice Contract managing swap market purchase orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/OrderRequestIssuer.sol)
contract BuyOrderIssuer is Issuer {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Permit;
    // This contract handles the submission and fulfillment of orders

    // 1. Order submitted and payment/asset escrowed
    // 2. Order fulfilled, escrow claimed, assets minted/burned

    // Fees are transfered when an order is closed (fulfilled or cancelled)

    struct OrderRequest {
        address recipient;
        address assetToken;
        address paymentToken;
        uint256 quantityIn;
    }

    struct OrderState {
        uint256 remainingOrder;
        uint256 remainingPercentageFees;
        uint256 feesEarned;
        uint256 received;
    }

    error ZeroValue();
    error NotRecipient();
    error OrderNotFound();
    error DuplicateOrder();
    error AmountTooLarge();
    error OrderTooSmall();

    bytes32 private constant ORDERREQUEST_TYPE_HASH = keccak256(
        "OrderRequest(bytes32 salt,address recipient,address assetToken,address paymentToken,uint256 quantityIn"
    );

    /// @dev unfilled orders
    mapping(bytes32 => OrderState) private _orders;

    function getOrderIdFromOrderRequest(OrderRequest memory order, bytes32 salt) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDERREQUEST_TYPE_HASH, salt, order.recipient, order.assetToken, order.paymentToken, order.quantityIn
            )
        );
    }

    function getOrderId(Order calldata order, bytes32 salt) external pure returns (bytes32) {
        return getOrderIdFromOrderRequest(getOrderRequestForOrder(order), salt);
    }

    function getOrderRequestForOrder(Order calldata order) public pure returns (OrderRequest memory) {
        return OrderRequest({
            recipient: order.recipient,
            assetToken: order.assetToken,
            paymentToken: order.paymentToken,
            quantityIn: order.paymentTokenQuantity + order.fee
        });
    }

    function isOrderActive(bytes32 id) external view returns (bool) {
        return _orders[id].remainingOrder > 0;
    }

    function getRemainingOrder(bytes32 id) public view returns (uint256) {
        return _orders[id].remainingOrder;
    }

    function getTotalReceived(bytes32 id) public view returns (uint256) {
        return _orders[id].received;
    }

    function getFeesForOrder(address token, uint256 amount)
        public
        view
        returns (uint256 flatFee, uint256 percentageFee)
    {
        if (address(orderFees) == address(0)) {
            return (0, 0);
        }
        return orderFees.feesForOrderUpfront(token, amount);
    }

    function requestOrder(OrderRequest calldata order, bytes32 salt) public {
        bytes32 orderId = getOrderIdFromOrderRequest(order, salt);
        _requestOrderAccounting(order, salt, orderId);

        // Escrow
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), order.quantityIn);
    }

    function requestOrderWithPermit(
        OrderRequest calldata order,
        bytes32 salt,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 orderId = getOrderIdFromOrderRequest(order, salt);
        _requestOrderAccounting(order, salt, orderId);

        // Escrow
        IERC20Permit(order.paymentToken).safePermit(msg.sender, address(this), value, deadline, v, r, s);
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), order.quantityIn);
    }

    function fillOrder(OrderRequest calldata order, bytes32 salt, uint256 fillAmount, uint256 receivedAmount)
        external
        onlyRole(OPERATOR_ROLE)
    {
        if (fillAmount == 0) revert ZeroValue();
        bytes32 orderId = getOrderIdFromOrderRequest(order, salt);
        OrderState memory orderState = _orders[orderId];
        if (orderState.remainingOrder == 0) revert OrderNotFound();
        if (fillAmount > orderState.remainingOrder) revert AmountTooLarge();

        _fillOrderAccounting(order, orderId, orderState, fillAmount, receivedAmount, fillAmount);
    }

    function requestCancel(OrderRequest calldata order, bytes32 salt) external {
        if (order.recipient != msg.sender) revert NotRecipient();
        bytes32 orderId = getOrderIdFromOrderRequest(order, salt);
        uint256 remainingOrder = _orders[orderId].remainingOrder;
        if (remainingOrder == 0) revert OrderNotFound();

        emit CancelRequested(orderId, order.recipient);
    }

    function cancelOrder(OrderRequest calldata order, bytes32 salt, string calldata reason)
        external
        onlyRole(OPERATOR_ROLE)
    {
        bytes32 orderId = getOrderIdFromOrderRequest(order, salt);
        OrderState memory orderState = _orders[orderId];
        _cancelOrderAccounting(order, orderId, orderState, reason);
    }

    function _requestOrderAccounting(OrderRequest calldata order, bytes32 salt, bytes32 orderId)
        internal
        virtual
        whenOrdersNotPaused
    {
        if (order.quantityIn == 0) revert ZeroValue();
        _checkRole(ASSETTOKEN_ROLE, order.assetToken);
        _checkRole(PAYMENTTOKEN_ROLE, order.paymentToken);
        if (_orders[orderId].remainingOrder > 0) revert DuplicateOrder();

        // Determine fees as if fees were added to order value
        (uint256 flatFee, uint256 percentageFee) = getFeesForOrder(order.paymentToken, order.quantityIn);
        uint256 totalFees = flatFee + percentageFee;
        if (totalFees >= order.quantityIn) revert OrderTooSmall();

        uint256 orderAmount = order.quantityIn - totalFees;
        _orders[orderId] = OrderState({
            remainingOrder: orderAmount,
            remainingPercentageFees: percentageFee,
            feesEarned: flatFee,
            received: 0
        });
        numOpenOrders++;
        Order memory bridgeOrderData = Order({
            recipient: order.recipient,
            assetToken: order.assetToken,
            paymentToken: order.paymentToken,
            sell: false,
            orderType: OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: orderAmount,
            price: 0,
            tif: TIF.GTC,
            fee: totalFees
        });
        emit OrderRequested(orderId, order.recipient, bridgeOrderData, salt);
    }

    function _fillOrderAccounting(
        OrderRequest calldata order,
        bytes32 orderId,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256 claimPaymentAmount
    ) internal virtual {
        emit OrderFill(orderId, order.recipient, fillAmount, receivedAmount);
        uint256 remainingOrder = orderState.remainingOrder - fillAmount;
        if (remainingOrder == 0) {
            emit OrderFulfilled(orderId, order.recipient);
            _closeOrder(orderId, order.paymentToken, orderState.remainingPercentageFees + orderState.feesEarned);
        } else {
            _orders[orderId].remainingOrder = remainingOrder;
            _orders[orderId].received = orderState.received + receivedAmount;
            uint256 collection = 0;
            if (orderState.remainingPercentageFees > 0) {
                collection = PrbMath.mulDiv(orderState.remainingPercentageFees, fillAmount, orderState.remainingOrder);
            }
            // Collect fees
            if (collection > 0) {
                _orders[orderId].remainingPercentageFees = orderState.remainingPercentageFees - collection;
                _orders[orderId].feesEarned = orderState.feesEarned + collection;
            }
        }

        // Mint asset
        IMintBurn(order.assetToken).mint(order.recipient, receivedAmount);
        // Claim payment
        if (claimPaymentAmount > 0) {
            IERC20(order.paymentToken).safeTransfer(msg.sender, claimPaymentAmount);
        }
    }

    function _cancelOrderAccounting(
        OrderRequest calldata order,
        bytes32 orderId,
        OrderState memory orderState,
        string calldata reason
    ) internal virtual {
        if (orderState.remainingOrder == 0) revert OrderNotFound();

        emit OrderCancelled(orderId, order.recipient, reason);

        // if no fills, then full refund
        uint256 refund = orderState.remainingOrder + orderState.remainingPercentageFees;
        if (refund + orderState.feesEarned == order.quantityIn) {
            _closeOrder(orderId, order.paymentToken, 0);
            refund = order.quantityIn;
        } else {
            _closeOrder(orderId, order.paymentToken, orderState.feesEarned);
        }

        // Return Escrow
        IERC20(order.paymentToken).safeTransfer(order.recipient, refund);
    }

    function _closeOrder(bytes32 orderId, address paymentToken, uint256 feesEarned) internal virtual {
        delete _orders[orderId];
        numOpenOrders--;

        if (feesEarned > 0) {
            IERC20(paymentToken).safeTransfer(treasury, feesEarned);
        }
    }
}
