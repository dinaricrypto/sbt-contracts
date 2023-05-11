// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "solady/auth/OwnableRoles.sol";
import "solady/utils/SafeTransferLib.sol";
import "openzeppelin/proxy/utils/Initializable.sol";
import "openzeppelin/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Permit.sol";
import "prb-math/Common.sol" as PrbMath;
import "./IOrderBridge.sol";
import "./IOrderFees.sol";
import "./IMintBurn.sol";

/// @notice Contract managing swap market orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/SwapOrderIssuer.sol)
contract SwapOrderIssuer is Initializable, OwnableRoles, UUPSUpgradeable, IOrderBridge {
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
    }

    error ZeroValue();
    error ZeroAddress();
    error UnsupportedToken();
    error NotRecipient();
    error OrderNotFound();
    error DuplicateOrder();
    error Paused();
    error FillTooLarge();
    error OrderTooSmall();

    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees orderFees);
    event TokenEnabled(address indexed token, bool enabled);
    event OrdersPaused(bool paused);

    // keccak256(OrderTicket(bytes32 salt, ...))
    // ... address recipient,address assetToken,address paymentToken,bool sell,uint256 quantityIn
    bytes32 private constant ORDERTICKET_TYPE_HASH = 0x96afe6b4a56935119c43c29fad54b6b65405604883803328f56826662a554433;

    address public treasury;

    IOrderFees public orderFees;

    /// @dev accepted tokens for this issuer
    mapping(address => bool) public tokenEnabled;

    /// @dev unfilled orders
    mapping(bytes32 => OrderState) private _orders;

    uint256 public numOpenOrders;

    bool public ordersPaused;

    function initialize(address owner, address treasury_, IOrderFees orderFees_) external initializer {
        if (treasury_ == address(0)) revert ZeroAddress();

        _initializeOwner(owner);

        treasury = treasury_;
        orderFees = orderFees_;
    }

    function operatorRole() external pure returns (uint256) {
        return _ROLE_1;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function setTreasury(address account) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();

        treasury = account;
        emit TreasurySet(account);
    }

    function setOrderFees(IOrderFees fees) external onlyOwner {
        orderFees = fees;
        emit OrderFeesSet(fees);
    }

    function setTokenEnabled(address token, bool enabled) external onlyOwner {
        tokenEnabled[token] = enabled;
        emit TokenEnabled(token, enabled);
    }

    function setOrdersPaused(bool pause) external onlyOwner {
        ordersPaused = pause;
        emit OrdersPaused(pause);
    }

    function getOrderId(SwapOrder calldata order, bytes32 salt) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDERTICKET_TYPE_HASH,
                salt,
                order.recipient,
                order.assetToken,
                order.paymentToken,
                order.sell,
                order.quantityIn
            )
        );
    }

    function isOrderActive(bytes32 id) external view returns (bool) {
        return _orders[id].remainingOrder > 0;
    }

    function getUnspentAmount(bytes32 id) external view returns (uint256) {
        return _orders[id].remainingOrder;
    }

    function getFeesForOrder(address assetToken, bool sell, uint256 amount) public view returns (uint256) {
        return address(orderFees) == address(0) ? 0 : orderFees.getFees(assetToken, sell, amount);
    }

    function requestOrder(SwapOrder calldata order, bytes32 salt) public {
        _requestOrderAccounting(order, salt);

        // Escrow
        SafeTransferLib.safeTransferFrom(
            order.sell ? order.assetToken : order.paymentToken, msg.sender, address(this), order.quantityIn
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
        IERC20Permit(tokenIn).permit(msg.sender, address(this), value, deadline, v, r, s);
        SafeTransferLib.safeTransferFrom(tokenIn, msg.sender, address(this), order.quantityIn);
    }

    function fillOrder(SwapOrder calldata order, bytes32 salt, uint256 spendAmount, uint256 receivedAmount)
        external
        onlyRoles(_ROLE_1)
    {
        if (spendAmount == 0) revert ZeroValue();
        bytes32 orderId = getOrderId(order, salt);
        OrderState memory orderState = _orders[orderId];
        if (orderState.remainingOrder == 0) revert OrderNotFound();
        if (spendAmount > orderState.remainingOrder) revert FillTooLarge();

        emit OrderFill(orderId, order.recipient, spendAmount);
        uint256 remainingUnspent = orderState.remainingOrder - spendAmount;
        uint256 collection = 0;
        if (remainingUnspent == 0) {
            delete _orders[orderId];
            numOpenOrders--;
            collection = orderState.remainingFees;
        } else {
            _orders[orderId].remainingOrder = remainingUnspent;
            if (orderState.remainingFees > 0) {
                collection = PrbMath.mulDiv(orderState.remainingFees, spendAmount, orderState.remainingOrder);
                _orders[orderId].remainingFees = orderState.remainingFees - collection;
            }
        }

        address tokenIn = order.sell ? order.assetToken : order.paymentToken;
        // Collect fees from tokenIn
        if (collection > 0) {
            SafeTransferLib.safeTransfer(tokenIn, treasury, collection);
        }
        // Mint/Burn
        if (order.sell) {
            // Forward proceeds
            SafeTransferLib.safeTransferFrom(order.paymentToken, msg.sender, order.recipient, receivedAmount);
            IMintBurn(order.assetToken).burn(spendAmount);
        } else {
            // Claim payment
            SafeTransferLib.safeTransfer(tokenIn, msg.sender, spendAmount);
            IMintBurn(order.assetToken).mint(order.recipient, receivedAmount);
        }
    }

    function requestCancel(SwapOrder calldata order, bytes32 salt) external {
        if (order.recipient != msg.sender) revert NotRecipient();
        bytes32 orderId = getOrderId(order, salt);
        uint256 remainingOrder = _orders[orderId].remainingOrder;
        if (remainingOrder == 0) revert OrderNotFound();

        emit CancelRequested(orderId, order.recipient);
    }

    function cancelOrder(SwapOrder calldata order, bytes32 salt, string calldata reason) external onlyRoles(_ROLE_1) {
        bytes32 orderId = getOrderId(order, salt);
        OrderState memory orderState = _orders[orderId];
        if (orderState.remainingOrder == 0) revert OrderNotFound();

        delete _orders[orderId];
        numOpenOrders--;
        emit OrderCancelled(orderId, order.recipient, reason);

        // Return Escrow
        SafeTransferLib.safeTransfer(
            order.sell ? order.assetToken : order.paymentToken, order.recipient, orderState.remainingOrder
        );
    }

    function _requestOrderAccounting(SwapOrder calldata order, bytes32 salt) internal {
        if (ordersPaused) revert Paused();
        if (order.quantityIn == 0) revert ZeroValue();
        if (!tokenEnabled[order.assetToken] || !tokenEnabled[order.paymentToken]) revert UnsupportedToken();
        bytes32 orderId = getOrderId(order, salt);
        if (_orders[orderId].remainingOrder > 0) revert DuplicateOrder();

        uint256 collection = getFeesForOrder(order.assetToken, order.sell, order.quantityIn);
        if (collection >= order.quantityIn) revert OrderTooSmall();

        uint256 orderAmount = order.quantityIn - collection;
        _orders[orderId] = OrderState({remainingOrder: orderAmount, remainingFees: collection});
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
            tif: TIF.DAY
        });
        if (order.sell) {
            bridgeOrderData.assetTokenQuantity = orderAmount;
        } else {
            bridgeOrderData.paymentTokenQuantity = orderAmount;
        }
        emit OrderRequested(orderId, order.recipient, bridgeOrderData, salt);
    }
}
