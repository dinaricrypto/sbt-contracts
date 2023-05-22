// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "solady/auth/OwnableRoles.sol";
import "solady/utils/SafeTransferLib.sol";
import "solady/utils/Multicallable.sol";
import "openzeppelin/proxy/utils/Initializable.sol";
import "openzeppelin/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Permit.sol";
import "prb-math/Common.sol" as PrbMath;
import "./IOrderBridge.sol";
import "./IOrderFees.sol";
import "./IMintBurn.sol";

/// @notice Contract managing limit orders for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/LimitOrderIssuer.sol)
contract LimitOrderIssuer is Initializable, OwnableRoles, UUPSUpgradeable, Multicallable, IOrderBridge {
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
    event OrdersPaused(bool paused);

    // keccak256(OrderTicket(bytes32 salt, ...))
    // ... address recipient,address assetToken,address paymentToken,bool sell,uint256 assetTokenQuantity,uint256 price
    bytes32 private constant ORDERTICKET_TYPE_HASH = 0x215ae685e66f9c7e06d95180afde8bab27cf88f0a82a87aa956e8e0ff57844a7;

    uint256 public constant ADMIN_ROLE = _ROLE_1;
    uint256 public constant OPERATOR_ROLE = _ROLE_2;
    uint256 public constant PAYMENTTOKEN_ROLE = _ROLE_3;
    uint256 public constant ASSETTOKEN_ROLE = _ROLE_4;

    address public treasury;

    IOrderFees public orderFees;

    /// @dev unfilled orders
    mapping(bytes32 => LimitOrderState) private _orders;

    uint256 public numOpenOrders;

    bool public ordersPaused;

    function initialize(address owner, address treasury_, IOrderFees orderFees_) external initializer {
        if (treasury_ == address(0)) revert ZeroAddress();

        _initializeOwner(owner);
        _grantRoles(owner, ADMIN_ROLE);

        treasury = treasury_;
        orderFees = orderFees_;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function setTreasury(address account) external onlyRoles(ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddress();

        treasury = account;
        emit TreasurySet(account);
    }

    function setOrderFees(IOrderFees fees) external onlyRoles(ADMIN_ROLE) {
        orderFees = fees;
        emit OrderFeesSet(fees);
    }

    function setOrdersPaused(bool pause) external onlyRoles(ADMIN_ROLE) {
        ordersPaused = pause;
        emit OrdersPaused(pause);
    }

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

    function getOrderId(Order calldata order, bytes32 salt) public pure returns (bytes32) {
        return getOrderIdFromLimitOrder(
            LimitOrder({
                recipient: order.recipient,
                assetToken: order.assetToken,
                paymentToken: order.paymentToken,
                sell: order.sell,
                assetTokenQuantity: order.assetTokenQuantity,
                price: order.price
            }),
            salt
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

    function getFeesForOrder(address assetToken, bool sell, uint256 assetTokenQuantity, uint256 price)
        public
        view
        returns (uint256, uint256)
    {
        uint256 orderValue = PrbMath.mulDiv18(assetTokenQuantity, price);
        uint256 collection = address(orderFees) == address(0) ? 0 : orderFees.getFees(assetToken, sell, orderValue);
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
            SafeTransferLib.safeTransferFrom(order.assetToken, msg.sender, address(this), order.assetTokenQuantity);
        } else {
            SafeTransferLib.safeTransferFrom(order.paymentToken, msg.sender, address(this), paymentTokenEscrowed);
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
            IERC20Permit(order.assetToken).permit(msg.sender, address(this), value, deadline, v, r, s);
            SafeTransferLib.safeTransferFrom(order.assetToken, msg.sender, address(this), order.assetTokenQuantity);
        } else {
            IERC20Permit(order.paymentToken).permit(msg.sender, address(this), value, deadline, v, r, s);
            SafeTransferLib.safeTransferFrom(order.paymentToken, msg.sender, address(this), paymentTokenEscrowed);
        }
    }

    // slither-disable-next-line cyclomatic-complexity
    function fillOrder(LimitOrder calldata order, bytes32 salt, uint256 fillAmount, uint256)
        external
        onlyRoles(OPERATOR_ROLE)
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
            (collection, proceedsToUser) = getFeesForOrder(order.assetToken, order.sell, fillAmount, order.price);
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
                SafeTransferLib.safeTransferFrom(order.paymentToken, msg.sender, order.recipient, proceedsToUser);
            }
            // Collect fees
            SafeTransferLib.safeTransferFrom(order.paymentToken, msg.sender, treasury, collection);
            // Burn
            IMintBurn(order.assetToken).burn(fillAmount);
        } else {
            // Collect fees
            if (collection > 0) {
                SafeTransferLib.safeTransfer(order.paymentToken, treasury, collection);
            }
            // Claim payment
            SafeTransferLib.safeTransfer(order.paymentToken, msg.sender, paymentClaim);
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
        onlyRoles(OPERATOR_ROLE)
    {
        bytes32 orderId = getOrderIdFromLimitOrder(order, salt);
        LimitOrderState memory orderState = _orders[orderId];
        if (orderState.unfilled == 0) revert OrderNotFound();

        delete _orders[orderId];
        numOpenOrders--;
        emit OrderCancelled(orderId, order.recipient, reason);

        // Return Escrow
        if (order.sell) {
            SafeTransferLib.safeTransfer(order.assetToken, order.recipient, orderState.unfilled);
        } else if (orderState.paymentTokenEscrowed > 0) {
            SafeTransferLib.safeTransfer(order.paymentToken, order.recipient, orderState.paymentTokenEscrowed);
        }
    }

    function _requestOrderAccounting(LimitOrder calldata order, bytes32 salt)
        internal
        returns (uint256 paymentTokenEscrowed)
    {
        if (order.assetTokenQuantity == 0) revert ZeroValue();
        if (!hasAnyRole(order.assetToken, ASSETTOKEN_ROLE)) revert UnsupportedToken();
        if (!hasAnyRole(order.paymentToken, PAYMENTTOKEN_ROLE)) revert UnsupportedToken();
        bytes32 orderId = getOrderIdFromLimitOrder(order, salt);
        if (_orders[orderId].unfilled > 0) revert DuplicateOrder();

        (uint256 collection, uint256 orderValue) =
            getFeesForOrder(order.assetToken, order.sell, order.assetTokenQuantity, order.price);
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
