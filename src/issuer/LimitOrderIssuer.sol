// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SafeERC20, IERC20, IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "prb-math/Common.sol" as PrbMath;
import "./Issuer.sol";
import "../IMintBurn.sol";

/// @notice Contract managing limit orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/LimitOrderIssuer.sol)
contract LimitOrderIssuer is Issuer {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Permit;
    // This contract handles the submission and fulfillment of orders
    // Takes fees from payment token

    // 1. Order submitted and payment/asset escrowed
    // 2. Order fulfilled, escrow claimed, assets minted/burned

    struct LimitOrder {
        address recipient;
        address assetToken;
        address paymentToken;
        bool sell;
        uint256 assetTokenQuantity;
        uint256 price;
    }

    struct LimitOrderState {
        uint256 unfilled;
        uint256 paymentTokenEscrowed;
    }

    error ZeroValue();
    error NotRecipient();
    error OrderNotFound();
    error DuplicateOrder();
    error Paused();
    error FillTooLarge();
    error OrderTooSmall();

    // keccak256(OrderTicket(bytes32 salt, ...))
    // ... address recipient,address assetToken,address paymentToken,bool sell,uint256 assetTokenQuantity,uint256 price
    bytes32 private constant ORDERTICKET_TYPE_HASH = 0x215ae685e66f9c7e06d95180afde8bab27cf88f0a82a87aa956e8e0ff57844a7;

    /// @dev unfilled orders
    mapping(bytes32 => LimitOrderState) private _orders;

    function getOrderIdFromLimitOrder(LimitOrder memory order, bytes32 salt) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDERTICKET_TYPE_HASH,
                salt,
                order.recipient,
                order.assetToken,
                order.paymentToken,
                order.sell,
                order.assetTokenQuantity,
                order.price
            )
        );
    }

    function getOrderId(Order calldata order, bytes32 salt) external pure returns (bytes32) {
        return getOrderIdFromLimitOrder(getLimitOrderForOrder(order), salt);
    }

    function getLimitOrderForOrder(Order calldata order) public pure returns (LimitOrder memory) {
        return LimitOrder({
            recipient: order.recipient,
            assetToken: order.assetToken,
            paymentToken: order.paymentToken,
            sell: order.sell,
            assetTokenQuantity: order.assetTokenQuantity,
            price: order.price
        });
    }

    function isOrderActive(bytes32 id) external view returns (bool) {
        return _orders[id].unfilled > 0;
    }

    function getRemainingOrder(bytes32 id) external view returns (uint256) {
        return _orders[id].unfilled;
    }

    function getPaymentEscrow(bytes32 id) external view returns (uint256) {
        return _orders[id].paymentTokenEscrowed;
    }

    function getFeesForLimitOrder(address assetToken, bool sell, uint256 assetTokenQuantity, uint256 price)
        public
        view
        returns (uint256, uint256)
    {
        uint256 orderValue = PrbMath.mulDiv18(assetTokenQuantity, price);
        uint256 collection = getFeesForOrder(assetToken, sell, orderValue);
        return (collection, orderValue);
    }

    function proceedsForFill(uint256 fillAmount, uint256 price) external pure returns (uint256) {
        return PrbMath.mulDiv18(fillAmount, price);
    }

    function requestOrder(LimitOrder calldata order, bytes32 salt) public {
        if (ordersPaused) revert Paused();

        uint256 paymentTokenEscrowed = _requestOrderAccounting(order, salt);

        // Escrow
        if (order.sell) {
            IERC20(order.assetToken).safeTransferFrom(msg.sender, address(this), order.assetTokenQuantity);
        } else {
            IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), paymentTokenEscrowed);
        }
    }

    function requestOrderWithPermit(
        LimitOrder calldata order,
        bytes32 salt,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (ordersPaused) revert Paused();

        uint256 paymentTokenEscrowed = _requestOrderAccounting(order, salt);

        // Escrow
        if (order.sell) {
            IERC20Permit(order.assetToken).safePermit(msg.sender, address(this), value, deadline, v, r, s);
            IERC20(order.assetToken).safeTransferFrom(msg.sender, address(this), order.assetTokenQuantity);
        } else {
            IERC20Permit(order.paymentToken).safePermit(msg.sender, address(this), value, deadline, v, r, s);
            IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), paymentTokenEscrowed);
        }
    }

    // slither-disable-next-line cyclomatic-complexity
    function fillOrder(LimitOrder calldata order, bytes32 salt, uint256 fillAmount, uint256)
        external
        onlyRole(OPERATOR_ROLE)
    {
        if (fillAmount == 0) revert ZeroValue();
        bytes32 orderId = getOrderIdFromLimitOrder(order, salt);
        LimitOrderState memory orderState = _orders[orderId];
        if (orderState.unfilled == 0) revert OrderNotFound();
        if (fillAmount > orderState.unfilled) revert FillTooLarge();

        // If sell, calc fees here, else use percent of escrowed payment
        uint256 collection = 0;
        uint256 proceedsToUser = 0;
        uint256 paymentClaim = 0;
        uint256 remainingUnfilled = orderState.unfilled - fillAmount;
        if (order.sell) {
            // Get fees
            (collection, proceedsToUser) = getFeesForLimitOrder(order.assetToken, order.sell, fillAmount, order.price);
            if (collection > proceedsToUser) {
                collection = proceedsToUser;
            }
            proceedsToUser -= collection;
        } else {
            // Calc fees
            uint256 remainingListValue = PrbMath.mulDiv18(orderState.unfilled, order.price);
            if (orderState.paymentTokenEscrowed > remainingListValue) {
                collection = PrbMath.mulDiv(
                    orderState.paymentTokenEscrowed - remainingListValue, fillAmount, orderState.unfilled
                );
            }
            paymentClaim = PrbMath.mulDiv18(fillAmount, order.price);
            if (remainingUnfilled == 0 && orderState.paymentTokenEscrowed > collection + paymentClaim) {
                paymentClaim += orderState.paymentTokenEscrowed - collection - paymentClaim;
            } else {
                _orders[orderId].paymentTokenEscrowed = orderState.paymentTokenEscrowed - collection - paymentClaim;
            }
        }

        emit OrderFill(orderId, order.recipient, fillAmount, order.sell ? proceedsToUser : fillAmount);
        if (remainingUnfilled == 0) {
            delete _orders[orderId];
            numOpenOrders--;
            emit OrderFulfilled(orderId, order.recipient);
        } else {
            _orders[orderId].unfilled = remainingUnfilled;
        }

        if (order.sell) {
            // Forward proceeds
            if (proceedsToUser > 0) {
                IERC20(order.paymentToken).safeTransferFrom(msg.sender, order.recipient, proceedsToUser);
            }
            // Collect fees
            IERC20(order.paymentToken).safeTransferFrom(msg.sender, treasury, collection);
            // Burn
            IMintBurn(order.assetToken).burn(fillAmount);
        } else {
            // Collect fees
            if (collection > 0) {
                IERC20(order.paymentToken).safeTransfer(treasury, collection);
            }
            // Claim payment
            IERC20(order.paymentToken).safeTransfer(msg.sender, paymentClaim);
            // Mint
            IMintBurn(order.assetToken).mint(order.recipient, fillAmount);
        }
    }

    function requestCancel(LimitOrder calldata order, bytes32 salt) external {
        if (order.recipient != msg.sender) revert NotRecipient();
        bytes32 orderId = getOrderIdFromLimitOrder(order, salt);
        uint256 unfilled = _orders[orderId].unfilled;
        if (unfilled == 0) revert OrderNotFound();

        emit CancelRequested(orderId, order.recipient);
    }

    function cancelOrder(LimitOrder calldata order, bytes32 salt, string calldata reason)
        external
        onlyRole(OPERATOR_ROLE)
    {
        bytes32 orderId = getOrderIdFromLimitOrder(order, salt);
        LimitOrderState memory orderState = _orders[orderId];
        if (orderState.unfilled == 0) revert OrderNotFound();

        delete _orders[orderId];
        numOpenOrders--;
        emit OrderCancelled(orderId, order.recipient, reason);

        // Return Escrow
        if (order.sell) {
            IERC20(order.assetToken).safeTransfer(order.recipient, orderState.unfilled);
        } else if (orderState.paymentTokenEscrowed > 0) {
            IERC20(order.paymentToken).safeTransfer(order.recipient, orderState.paymentTokenEscrowed);
        }
    }

    function _requestOrderAccounting(LimitOrder calldata order, bytes32 salt)
        internal
        returns (uint256 paymentTokenEscrowed)
    {
        if (order.assetTokenQuantity == 0) revert ZeroValue();
        _checkRole(ASSETTOKEN_ROLE, order.assetToken);
        _checkRole(PAYMENTTOKEN_ROLE, order.paymentToken);
        bytes32 orderId = getOrderIdFromLimitOrder(order, salt);
        if (_orders[orderId].unfilled > 0) revert DuplicateOrder();

        (uint256 collection, uint256 orderValue) =
            getFeesForLimitOrder(order.assetToken, order.sell, order.assetTokenQuantity, order.price);
        paymentTokenEscrowed = 0;
        if (!order.sell) {
            paymentTokenEscrowed = orderValue + collection;
            if (paymentTokenEscrowed == 0) revert OrderTooSmall();
        }
        _orders[orderId] =
            LimitOrderState({unfilled: order.assetTokenQuantity, paymentTokenEscrowed: paymentTokenEscrowed});
        numOpenOrders++;
        emit OrderRequested(
            orderId,
            order.recipient,
            Order({
                recipient: order.recipient,
                assetToken: order.assetToken,
                paymentToken: order.paymentToken,
                sell: order.sell,
                orderType: OrderType.LIMIT,
                assetTokenQuantity: order.assetTokenQuantity,
                paymentTokenQuantity: 0,
                price: order.price,
                tif: TIF.GTC,
                fee: collection
            }),
            salt
        );
    }
}
