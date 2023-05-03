// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "solady/auth/OwnableRoles.sol";
import "solady/utils/SafeTransferLib.sol";
import "openzeppelin/proxy/utils/Initializable.sol";
import "openzeppelin/proxy/utils/UUPSUpgradeable.sol";
import "./IVaultBridge.sol";
import "./IOrderFees.sol";
import "./IMintBurn.sol";

/// @notice Bridge interface managing swaps for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/Bridge.sol)
contract VaultBridge is Initializable, OwnableRoles, UUPSUpgradeable, IVaultBridge {
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

    error ZeroValue();
    error UnsupportedPaymentToken();
    error NoProxyOrders();
    error OrderNotFound();
    error DuplicateOrder();
    error Paused();
    error FillTooLarge();

    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees orderFees);
    event PaymentTokenEnabled(address indexed token, bool enabled);
    event OrdersPaused(bool paused);

    // keccak256(OrderTicket(bytes32 salt, ...))
    // ... address user,address assetToken,address paymentToken,bool sell,uint8 orderType,uint256 amount,uint8 tif
    bytes32 private constant ORDERTICKET_TYPE_HASH = 0xa0faa2afef6a26ed0bf51fd8a0ad3f748a44267351b18c6257e625624ccfcb61;

    address public treasury;

    IOrderFees public orderFees;

    /// @dev accepted payment tokens for this issuer
    mapping(address => bool) public paymentTokenEnabled;

    /// @dev unfilled orders
    mapping(bytes32 => uint256) private _orders;

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
                order.tif
            )
        );
    }

    function isOrderActive(bytes32 id) external view returns (bool) {
        return _orders[id] > 0;
    }

    function getUnfilledAmount(bytes32 id) external view returns (uint256) {
        return _orders[id];
    }

    function requestOrder(Order calldata order, bytes32 salt) external {
        if (ordersPaused) revert Paused();
        if (order.user != msg.sender) revert NoProxyOrders();
        uint256 orderAmount = order.sell ? order.assetTokenQuantity : order.paymentTokenQuantity;
        if (orderAmount == 0) revert ZeroValue();
        if (!paymentTokenEnabled[order.paymentToken]) revert UnsupportedPaymentToken();
        bytes32 orderId = getOrderId(order, salt);
        if (_orders[orderId] > 0) revert DuplicateOrder();

        // Emit the data, store the hash
        _orders[orderId] = orderAmount;
        numOpenOrders++;
        emit OrderRequested(orderId, order.user, order, salt);

        // Escrow
        SafeTransferLib.safeTransferFrom(
            order.sell ? order.assetToken : order.paymentToken, msg.sender, address(this), orderAmount
        );
    }

    function fillOrder(Order calldata order, bytes32 salt, uint256 fillAmount, uint256 resultAmount)
        external
        onlyRoles(_ROLE_1)
    {
        bytes32 orderId = getOrderId(order, salt);
        uint256 unfilled = _orders[orderId];
        if (unfilled == 0) revert OrderNotFound();
        if (fillAmount > unfilled) revert FillTooLarge();

        uint256 remainingUnfilled = unfilled - fillAmount;
        _orders[orderId] = remainingUnfilled;
        numOpenOrders--;

        // Get fees
        uint256 collection = orderFees.getFees(order.sell, false, resultAmount);
        uint256 proceedsToUser;
        if (collection > resultAmount) {
            collection = resultAmount;
        } else {
            proceedsToUser = resultAmount - collection;
        }
        emit OrderFill(orderId, order.user, fillAmount, proceedsToUser);
        if (remainingUnfilled == 0) {
            uint256 orderAmount = order.sell ? order.assetTokenQuantity : order.paymentTokenQuantity;
            emit OrderFulfilled(orderId, order.user, orderAmount);
        }

        if (order.sell) {
            // Collect fees
            SafeTransferLib.safeTransferFrom(order.paymentToken, msg.sender, treasury, collection);
            // Forward proceeds
            SafeTransferLib.safeTransferFrom(order.paymentToken, msg.sender, order.user, proceedsToUser);
            // Burn
            IMintBurn(order.assetToken).burn(fillAmount);
        } else {
            // Collect fees
            IMintBurn(order.assetToken).mint(treasury, collection);
            // Mint
            IMintBurn(order.assetToken).mint(order.user, proceedsToUser);
            // Claim payment
            SafeTransferLib.safeTransfer(order.paymentToken, msg.sender, fillAmount);
        }
    }

    function requestCancel(Order calldata order, bytes32 salt) external {
        if (order.user != msg.sender) revert NoProxyOrders();
        bytes32 orderId = getOrderId(order, salt);
        uint256 unfilled = _orders[orderId];
        if (unfilled == 0) revert OrderNotFound();

        emit CancelRequested(orderId, order.user);
    }

    function cancelOrder(Order calldata order, bytes32 salt, string calldata reason) external onlyRoles(_ROLE_1) {
        bytes32 orderId = getOrderId(order, salt);
        uint256 unfilled = _orders[orderId];
        if (unfilled == 0) revert OrderNotFound();

        delete _orders[orderId];
        emit OrderCancelled(orderId, order.user, reason);

        uint256 orderAmount = order.sell ? order.assetTokenQuantity : order.paymentTokenQuantity;
        uint256 filled = orderAmount - unfilled;
        if (filled != 0) {
            emit OrderFulfilled(orderId, order.user, filled);
        }
    }
}
