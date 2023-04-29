// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solady/auth/OwnableRoles.sol";
import "solady/utils/SafeTransferLib.sol";
import "solady/utils/FixedPointMathLib.sol";
import "openzeppelin/proxy/utils/Initializable.sol";
import "openzeppelin/proxy/utils/UUPSUpgradeable.sol";
import "./IMintBurn.sol";

/// @notice Bridge interface managing swaps for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/Bridge.sol)
contract Bridge is Initializable, OwnableRoles, UUPSUpgradeable {
    using FixedPointMathLib for uint256;
    // This contract handles the submission and fulfillment of orders
    // Takes fees from payment token
    // TODO: submit by sig - forwarder/gsn support?
    // TODO: liquidity pools for cross-chain swaps
    // TODO: should we allow beneficiary != submit msg.sender?
    // TODO: cancel orders
    // TODO: forwarder support for fulfiller - worker/custodian separation

    // 1. Order submitted and payment/asset escrowed
    // 2. Order fulfilled, escrow claimed, assets minted/burned

    enum OrderAction {
        BUY,
        SELL
    }

    enum OrderType {
        MARKET,
        LIMIT,
        STOP
    }

    /// @dev Data model for structured orders
    struct Order {
        bytes32 salt;
        address user;
        address assetToken;
        address paymentToken;
        uint256 assetTokenQuantity;
        uint256 assetTokenPrice;
        uint64 timeInForce;
    }

    /// @dev Data model for atomic swaps
    struct Swap {
        address user;
        address assetToken;
        address paymentToken;
        OrderAction action;
        uint256 amount;
    }

    struct OrderState {
        uint256 feeCollection;
        uint256 orderAmount;
    }

    struct Fees {
        uint64 purchaseFee;
        uint64 saleFee;
    }

    error ZeroValue();
    error FeeTooLarge();
    error UnsupportedPaymentToken();
    error NoProxyOrders();
    error OrderNotFound();
    error DuplicateOrder();
    error Paused();

    event TreasurySet(address indexed treasury);
    event FeesSet(Fees fees);
    event PaymentTokenEnabled(address indexed token, bool enabled);
    event OrdersPaused(bool paused);
    event SwapSubmitted(bytes32 indexed swapId, address indexed user, Swap swap, uint256 orderAmount);
    event SwapFulfilled(bytes32 indexed swapId, address indexed user, uint256 amount);

    // keccak256(SwapTicket(bytes32 salt,address user,address assetToken,address paymentToken,uint8 action,uint256 amount))
    bytes32 private constant SWAPTICKET_TYPE_HASH = 0xbdf8c391853a76393ea7fba522fb5b119dbcd41e00e57a0db66763f95fb87367;

    address public treasury;

    Fees public fees;

    /// @dev accepted payment tokens for this issuer
    mapping(address => bool) public paymentTokenEnabled;

    /// @dev unfulfilled swap orders
    mapping(bytes32 => OrderState) private _swaps;

    bool public ordersPaused;

    function initialize(address owner, address treasury_) external initializer {
        _initializeOwner(owner);

        treasury = treasury_;
    }

    function operatorRole() external pure returns (uint256) {
        return _ROLE_1;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function isSwapActive(bytes32 swapId) external view returns (bool) {
        return _swaps[swapId].orderAmount > 0;
    }

    function hashSwapTicket(Swap calldata swap, bytes32 salt) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                SWAPTICKET_TYPE_HASH, salt, swap.user, swap.assetToken, swap.paymentToken, swap.action, swap.amount
            )
        );
    }

    function setTreasury(address account) external onlyOwner {
        treasury = account;
        emit TreasurySet(account);
    }

    function setFees(Fees calldata fees_) external onlyOwner {
        if (fees_.purchaseFee > 1 ether) revert FeeTooLarge();
        if (fees_.saleFee > 1 ether) revert FeeTooLarge();

        fees = fees_;
        emit FeesSet(fees_);
    }

    function setPaymentTokenEnabled(address token, bool enabled) external onlyOwner {
        paymentTokenEnabled[token] = enabled;
        emit PaymentTokenEnabled(token, enabled);
    }

    function setOrdersPaused(bool pause) external onlyOwner {
        ordersPaused = pause;
        emit OrdersPaused(pause);
    }

    function submitSwap(Swap calldata swap, bytes32 salt) external {
        if (ordersPaused) revert Paused();
        if (swap.user != msg.sender) revert NoProxyOrders();
        if (swap.amount == 0) revert ZeroValue();
        if (!paymentTokenEnabled[swap.paymentToken]) revert UnsupportedPaymentToken();
        bytes32 swapId = hashSwapTicket(swap, salt);
        if (_swaps[swapId].orderAmount > 0) revert DuplicateOrder();

        // Calculate fees
        uint256 collection = swap.action == OrderAction.BUY ? (swap.amount / 1 ether) * fees.purchaseFee : 0;
        OrderState memory swapState = OrderState({feeCollection: collection, orderAmount: swap.amount - collection});

        // Emit the data, store the hash
        _swaps[swapId] = swapState;
        emit SwapSubmitted(swapId, swap.user, swap, swapState.orderAmount);

        // Escrow
        SafeTransferLib.safeTransferFrom(
            swap.action == OrderAction.BUY ? swap.paymentToken : swap.assetToken, msg.sender, address(this), swap.amount
        );
    }

    function fulfillSwap(Swap calldata swap, bytes32 salt, uint256 amount) external {
        bytes32 swapId = hashSwapTicket(swap, salt);
        OrderState memory swapState = _swaps[swapId];
        if (swapState.orderAmount == 0) revert OrderNotFound();

        delete _swaps[swapId];
        emit SwapFulfilled(swapId, swap.user, amount);

        if (swap.action == OrderAction.BUY) {
            // Mint
            IMintBurn(swap.assetToken).mint(swap.user, amount);
            // Distribute fees
            SafeTransferLib.safeTransfer(swap.paymentToken, treasury, swapState.feeCollection);
            // Claim payment
            SafeTransferLib.safeTransfer(swap.paymentToken, msg.sender, swapState.orderAmount);
        } else {
            // Collect fees
            uint256 collection = amount.mulWad(fees.saleFee);
            SafeTransferLib.safeTransferFrom(swap.paymentToken, msg.sender, treasury, collection);
            // Forward proceeds
            SafeTransferLib.safeTransferFrom(swap.paymentToken, msg.sender, swap.user, amount - collection);
            // Burn
            IMintBurn(swap.assetToken).burn(swap.amount);
        }
    }
}
