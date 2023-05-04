// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "solady/auth/OwnableRoles.sol";
import "solady/utils/SafeTransferLib.sol";
import "openzeppelin/proxy/utils/Initializable.sol";
import "openzeppelin/proxy/utils/UUPSUpgradeable.sol";
import "prb-math/Common.sol" as PrbMath;
import "./IVaultBridge.sol";
import "./IOrderFees.sol";
import "./IMintBurn.sol";

/// @notice Bridge interface managing limit orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/LimitOrderBridge.sol)
contract LimitOrderBridge is Initializable, OwnableRoles, UUPSUpgradeable, IVaultBridge {
    // This contract handles the submission and fulfillment of orders
    // Takes fees from payment token
    // TODO: submit by sig - forwarder/gsn support?
    // TODO: liquidity pools for cross-chain swaps
    // TODO: should we allow beneficiary != submit msg.sender?
    // TODO: forwarder support for fulfiller - worker/custodian separation
    // TODO: whitelist asset tokens?
    // TODO: per-asset order pause

    // 1. Order submitted and payment/asset escrowed
    // 2. Order fulfilled, escrow claimed, assets minted/burned

    struct LimitOrderState {
        uint256 unfilled;
        uint256 paymentTokenEscrowed;
    }

    error ZeroValue();
    error UnsupportedPaymentToken();
    error NoProxyOrders();
    error OnlyLimitOrders();
    error OrderNotFound();
    error DuplicateOrder();
    error Paused();
    error FillTooLarge();
    error NotBuyOrder();
    error OrderTooSmall();

    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees orderFees);
    event PaymentTokenEnabled(address indexed token, bool enabled);
    event OrdersPaused(bool paused);

    // keccak256(OrderTicket(bytes32 salt, ...))
    // ... address user,address assetToken,address paymentToken,bool sell,uint8 orderType,uint256 assetTokenQuantity,uint256 paymentTokenQuantity,uint8 tif
    bytes32 private constant ORDERTICKET_TYPE_HASH = 0x709b33c75deed16be0943f3ffa6358f012c9bb13ab7eb6365596e358c0f26e15;

    address public treasury;

    IOrderFees public orderFees;

    /// @dev accepted payment tokens for this issuer
    mapping(address => bool) public paymentTokenEnabled;

    /// @dev unfilled orders
    mapping(bytes32 => LimitOrderState) private _orders;

    uint256 public numOpenOrders;

    bool public ordersPaused;

    function initialize(address owner, address treasury_, IOrderFees orderFees_) external initializer {
        _initializeOwner(owner);

        treasury = treasury_;
        orderFees = orderFees_;
    }

    function operatorRole() external pure returns (uint256) {
        return _ROLE_1;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function setTreasury(address account) external onlyOwner {
        treasury = account;
        emit TreasurySet(account);
    }

    function setOrderFees(IOrderFees fees) external onlyOwner {
        orderFees = fees;
        emit OrderFeesSet(fees);
    }

    function setPaymentTokenEnabled(address token, bool enabled) external onlyOwner {
        paymentTokenEnabled[token] = enabled;
        emit PaymentTokenEnabled(token, enabled);
    }

    function setOrdersPaused(bool pause) external onlyOwner {
        ordersPaused = pause;
        emit OrdersPaused(pause);
    }

    function getOrderId(Order calldata order, bytes32 salt) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDERTICKET_TYPE_HASH,
                salt,
                order.user,
                order.assetToken,
                order.paymentToken,
                order.sell,
                order.orderType,
                order.assetTokenQuantity,
                order.paymentTokenQuantity,
                order.price,
                order.tif
            )
        );
    }

    function isOrderActive(bytes32 id) external view returns (bool) {
        return _orders[id].unfilled > 0;
    }

    function getUnfilledAmount(bytes32 id) external view returns (uint256) {
        return _orders[id].unfilled;
    }

    function getPaymentEscrow(bytes32 id) external view returns (uint256) {
        return _orders[id].paymentTokenEscrowed;
    }

    function totalPaymentForOrder(Order calldata order) external view returns (uint256) {
        if (order.sell) revert NotBuyOrder();

        uint256 orderValue = PrbMath.mulDiv18(order.assetTokenQuantity, order.price);
        uint256 collection = orderFees.getFees(order.sell, orderValue);
        return orderValue + collection;
    }

    function proceedsForFill(uint256 fillAmount, uint256 price) external pure returns (uint256) {
        return PrbMath.mulDiv18(fillAmount, price);
    }

    function requestOrder(Order calldata order, bytes32 salt) external {
        if (ordersPaused) revert Paused();
        if (order.orderType != OrderType.LIMIT) revert OnlyLimitOrders();
        if (order.user != msg.sender) revert NoProxyOrders();
        if (order.assetTokenQuantity == 0) revert ZeroValue();
        if (!paymentTokenEnabled[order.paymentToken]) revert UnsupportedPaymentToken();
        bytes32 orderId = getOrderId(order, salt);
        if (_orders[orderId].unfilled > 0) revert DuplicateOrder();

        uint256 paymentTokenEscrowed;
        if (!order.sell) {
            uint256 orderValue = PrbMath.mulDiv18(order.assetTokenQuantity, order.price);
            uint256 collection = orderFees.getFees(order.sell, orderValue);
            paymentTokenEscrowed = orderValue + collection;
            if (paymentTokenEscrowed == 0) revert OrderTooSmall();
        }
        _orders[orderId] =
            LimitOrderState({unfilled: order.assetTokenQuantity, paymentTokenEscrowed: paymentTokenEscrowed});
        numOpenOrders++;
        emit OrderRequested(orderId, order.user, order, salt);

        // Escrow
        if (order.sell) {
            SafeTransferLib.safeTransferFrom(order.assetToken, msg.sender, address(this), order.assetTokenQuantity);
        } else {
            SafeTransferLib.safeTransferFrom(order.paymentToken, msg.sender, address(this), paymentTokenEscrowed);
        }
    }

    function fillOrder(Order calldata order, bytes32 salt, uint256 fillAmount, uint256) external onlyRoles(_ROLE_1) {
        if (fillAmount == 0) revert ZeroValue();
        bytes32 orderId = getOrderId(order, salt);
        LimitOrderState memory orderState = _orders[orderId];
        if (orderState.unfilled == 0) revert OrderNotFound();
        if (fillAmount > orderState.unfilled) revert FillTooLarge();

        emit OrderFill(orderId, order.user, fillAmount);
        uint256 remainingUnfilled = orderState.unfilled - fillAmount;
        if (remainingUnfilled == 0) {
            delete _orders[orderId];
            numOpenOrders--;
            emit OrderFulfilled(orderId, order.user, order.assetTokenQuantity);
        } else {
            _orders[orderId].unfilled = remainingUnfilled;
        }

        // If sell, calc fees here, else use percent of escrowed payment
        if (order.sell) {
            uint256 proceedsDue = PrbMath.mulDiv18(fillAmount, order.price);
            // Get fees
            uint256 collection = orderFees.getFees(true, proceedsDue);
            uint256 proceedsToUser;
            if (collection > proceedsDue) {
                collection = proceedsDue;
            } else {
                proceedsToUser = proceedsDue - collection;
                // Forward proceeds
                SafeTransferLib.safeTransferFrom(order.paymentToken, msg.sender, order.user, proceedsToUser);
            }
            // Collect fees
            SafeTransferLib.safeTransferFrom(order.paymentToken, msg.sender, treasury, collection);
            // Burn
            IMintBurn(order.assetToken).burn(fillAmount);
        } else {
            // Calc fees
            uint256 remainingListValue = PrbMath.mulDiv18(orderState.unfilled, order.price);
            uint256 collection;
            if (orderState.paymentTokenEscrowed > remainingListValue) {
                collection = PrbMath.mulDiv(
                    orderState.paymentTokenEscrowed - remainingListValue, fillAmount, orderState.unfilled
                );
            }
            uint256 paymentClaim = PrbMath.mulDiv18(fillAmount, order.price);
            if (remainingUnfilled == 0 && orderState.paymentTokenEscrowed > collection + paymentClaim) {
                paymentClaim += orderState.paymentTokenEscrowed - collection - paymentClaim;
            } else {
                _orders[orderId].paymentTokenEscrowed = orderState.paymentTokenEscrowed - collection - paymentClaim;
            }
            // Collect fees
            if (collection > 0) {
                SafeTransferLib.safeTransfer(order.paymentToken, treasury, collection);
            }
            // Claim payment
            SafeTransferLib.safeTransfer(order.paymentToken, msg.sender, paymentClaim);
            // Mint
            IMintBurn(order.assetToken).mint(order.user, fillAmount);
        }
    }

    function requestCancel(Order calldata order, bytes32 salt) external {
        if (order.user != msg.sender) revert NoProxyOrders();
        bytes32 orderId = getOrderId(order, salt);
        uint256 unfilled = _orders[orderId].unfilled;
        if (unfilled == 0) revert OrderNotFound();

        emit CancelRequested(orderId, order.user);
    }

    function cancelOrder(Order calldata order, bytes32 salt, string calldata reason) external onlyRoles(_ROLE_1) {
        bytes32 orderId = getOrderId(order, salt);
        LimitOrderState memory orderState = _orders[orderId];
        if (orderState.unfilled == 0) revert OrderNotFound();

        delete _orders[orderId];
        numOpenOrders--;
        emit OrderCancelled(orderId, order.user, reason);

        uint256 filled = order.assetTokenQuantity - orderState.unfilled;
        if (filled != 0) {
            emit OrderFulfilled(orderId, order.user, filled);
        }

        // Return Escrow
        if (order.sell) {
            SafeTransferLib.safeTransfer(order.assetToken, order.user, orderState.unfilled);
        } else if (orderState.paymentTokenEscrowed > 0) {
            SafeTransferLib.safeTransfer(order.paymentToken, order.user, orderState.paymentTokenEscrowed);
        }
    }
}
