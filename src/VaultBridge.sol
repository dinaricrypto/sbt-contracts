// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "solady/auth/OwnableRoles.sol";
import "solady/utils/SafeTransferLib.sol";
import "openzeppelin/proxy/utils/Initializable.sol";
import "openzeppelin/proxy/utils/UUPSUpgradeable.sol";
import "./IOrderFees.sol";
import "./IMintBurn.sol";

/// @notice Bridge interface managing swaps for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/Bridge.sol)
contract VaultBridge is Initializable, OwnableRoles, UUPSUpgradeable {
    // This contract handles the submission and fulfillment of orders
    // Takes fees from payment token
    // TODO: submit by sig - forwarder/gsn support?
    // TODO: liquidity pools for cross-chain swaps
    // TODO: should we allow beneficiary != submit msg.sender?
    // TODO: cancel orders
    // TODO: forwarder support for fulfiller - worker/custodian separation
    // TODO: whitelist asset tokens?

    // 1. Order submitted and payment/asset escrowed
    // 2. Order fulfilled, escrow claimed, assets minted/burned

    /// @dev Data model for atomic swaps
    struct Swap {
        address user;
        address assetToken;
        address paymentToken;
        bool sell;
        uint256 amount;
    }

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
    event SwapSubmitted(bytes32 indexed swapId, address indexed user, Swap swap);
    event SwapFulfilled(bytes32 indexed swapId, address indexed user, uint256 fillAmount, uint256 proceeds);

    // keccak256(SwapTicket(bytes32 salt,address user,address assetToken,address paymentToken,bool sell,uint256 amount))
    bytes32 private constant SWAPTICKET_TYPE_HASH = 0xb9a9d2af18036c7d42c1a8a82a27fc2f128e6bcd7b9a70c0b8e777098b9740e6;

    address public treasury;

    IOrderFees public orderFees;

    /// @dev accepted payment tokens for this issuer
    mapping(address => bool) public paymentTokenEnabled;

    /// @dev unfulfilled swap orders
    mapping(bytes32 => uint256) private _swaps;

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

    function isSwapActive(bytes32 swapId) external view returns (bool) {
        return _swaps[swapId] > 0;
    }

    function hashSwapTicket(Swap calldata swap, bytes32 salt) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                SWAPTICKET_TYPE_HASH, salt, swap.user, swap.assetToken, swap.paymentToken, swap.sell, swap.amount
            )
        );
    }

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

    function submitSwap(Swap calldata swap, bytes32 salt) external {
        if (ordersPaused) revert Paused();
        if (swap.user != msg.sender) revert NoProxyOrders();
        if (swap.amount == 0) revert ZeroValue();
        if (!paymentTokenEnabled[swap.paymentToken]) revert UnsupportedPaymentToken();
        bytes32 swapId = hashSwapTicket(swap, salt);
        if (_swaps[swapId] > 0) revert DuplicateOrder();

        // Emit the data, store the hash
        _swaps[swapId] = swap.amount;
        emit SwapSubmitted(swapId, swap.user, swap);

        // Escrow
        SafeTransferLib.safeTransferFrom(
            swap.sell ? swap.assetToken : swap.paymentToken, msg.sender, address(this), swap.amount
        );
    }

    function fulfillSwap(Swap calldata swap, bytes32 salt, uint256 fillAmount, uint256 proceeds) external {
        bytes32 swapId = hashSwapTicket(swap, salt);
        uint256 swapRemaining = _swaps[swapId];
        if (swapRemaining == 0) revert OrderNotFound();
        if (fillAmount > swapRemaining) revert FillTooLarge();

        delete _swaps[swapId];
        emit SwapFulfilled(swapId, swap.user, fillAmount, proceeds);

        // Get fees
        uint256 collection = orderFees.getFees(swap.sell, false, proceeds);
        if (swap.sell) {
            // Collect fees
            SafeTransferLib.safeTransferFrom(swap.paymentToken, msg.sender, treasury, collection);
            // Forward proceeds
            SafeTransferLib.safeTransferFrom(swap.paymentToken, msg.sender, swap.user, proceeds - collection);
            // Burn
            IMintBurn(swap.assetToken).burn(fillAmount);
        } else {
            // Collect fees
            SafeTransferLib.safeTransferFrom(swap.assetToken, msg.sender, treasury, collection);
            // Forward proceeds
            SafeTransferLib.safeTransferFrom(swap.assetToken, msg.sender, swap.user, proceeds - collection);
            // Mint
            IMintBurn(swap.assetToken).mint(swap.user, fillAmount);
        }
    }
}
