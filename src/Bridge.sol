// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solady/auth/OwnableRoles.sol";
import "solady/utils/ECDSA.sol";
import "solady/utils/EIP712.sol";
import "solady/utils/SafeTransferLib.sol";
import "./IMintBurn.sol";

/// @notice Bridge interface managing swaps for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/Bridge.sol)
contract Bridge is OwnableRoles, EIP712 {
    // This contract handles the submission and fulfillment of orders
    // forwarder/gsn support?
    // TODO: upgradeable, pausable
    // TODO: fees
    // How do bridges maintain quotes and slippage checks?
    // Is "emit the data, store the hash" useful anywhere - see synapse

    // 1. Order submitted and payment escrowed
    // 2. Order fulfilled and escrow claimed
    // 2a. If order failed, escrow released

    struct Quote {
        address assetToken;
        address paymentToken;
        uint32 blockNumber; // change to time if needed
        uint224 price;
    }

    struct OrderInfo {
        address user;
        Quote quote;
        // TODO: tighter packing
        uint256 amount;
        uint256 maxSlippage;
    }

    error UnsupportedPaymentToken();
    error WrongPriceOracle();
    error NoProxyOrders();
    error OrderNotFound();
    error SlippageLimitExceeded();

    event PaymentTokenSet(address indexed token, bool enabled);
    event PriceOracleSet(address indexed oracle, bool enabled);
    event PurchaseSubmitted(bytes32 indexed orderId, address indexed user, OrderInfo orderInfo);
    event RedemptionSubmitted(bytes32 indexed orderId, address indexed user, OrderInfo orderInfo);

    // keccak256(Quote(...))
    bytes32 public constant QUOTE_TYPE_HASH = 0xc5ddd247b301bf2eeb74a33f6e27e98a8f79747c3449d0bb82beb501b34d3b43;
    // keccak256(OrderInfo(...))
    bytes32 public constant ORDER_TYPE_HASH = 0x81b90cb8115e6356acd6aef528d0f8c249d695ea3aba8e195aad63736f1cff9d;

    /// @dev How long a quote is valid in blocks
    uint32 public quoteDuration;

    /// @dev accepted payment tokens for this issuer
    mapping(address => bool) public paymentToken;

    /// @dev trusted oracles for this issuer
    mapping(address => bool) public priceOracle;

    /// @dev unfulfilled orders
    // TODO: make collection efficient
    // TODO: need beneficiary account and price info
    // TODO: generalize order queuing across order types? support limit in future?
    // TODO: consider time received?
    // TODO: add proof of fulfillment?
    mapping(bytes32 => bool) private _purchases;
    mapping(bytes32 => bool) private _redemptions;

    // per block quote (price, time)
    // - can this be a pass-through calldata quote signed by our oracle? then we can serve from out API and save gas
    // - check how quotes currently work in bridges etc.
    // max slippage
    // amount
    constructor(uint32 quoteDuration_) {
        quoteDuration = quoteDuration_;
    }

    function operatorRole() external pure returns (uint256) {
        return _ROLE_1;
    }

    function isPurchaseActive(bytes32 orderId) external view returns (bool) {
        return _purchases[orderId];
    }

    function isRedemptionActive(bytes32 orderId) external view returns (bool) {
        return _redemptions[orderId];
    }

    function hashQuote(Quote memory quote) public pure returns (bytes32) {
        return
            keccak256(abi.encode(ORDER_TYPE_HASH, quote.assetToken, quote.paymentToken, quote.blockNumber, quote.price));
    }

    function hashOrderInfo(OrderInfo memory orderInfo) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                QUOTE_TYPE_HASH,
                orderInfo.user,
                orderInfo.quote.assetToken,
                orderInfo.quote.paymentToken,
                orderInfo.quote.blockNumber,
                orderInfo.quote.price,
                orderInfo.amount,
                orderInfo.maxSlippage
            )
        );
    }

    function setPaymentToken(address token, bool enabled) external onlyOwner {
        paymentToken[token] = enabled;
        emit PaymentTokenSet(token, enabled);
    }

    function setPriceOracle(address oracle, bool enabled) external onlyOwner {
        priceOracle[oracle] = enabled;
        emit PriceOracleSet(oracle, enabled);
    }

    function submitPurchase(OrderInfo calldata order, bytes calldata signedQuote) external {
        if (order.user != msg.sender) revert NoProxyOrders(); // TODO: should we allow beneficiary != msg.sender?
        if (!paymentToken[order.quote.paymentToken]) revert UnsupportedPaymentToken();
        address oracleAddress = ECDSA.recoverCalldata(_hashTypedData(hashQuote(order.quote)), signedQuote);
        if (!priceOracle[oracleAddress]) revert WrongPriceOracle();

        // TODO: support multiple identical orders from the same account
        bytes32 orderId = hashOrderInfo(order);
        _purchases[orderId] = true;
        emit PurchaseSubmitted(orderId, order.user, order);

        // Move payment tokens
        // TODO: is there a more secure way than holding all this here?
        uint256 paymentAmount = order.amount * order.quote.price;
        SafeTransferLib.safeTransferFrom(order.quote.paymentToken, msg.sender, address(this), paymentAmount);
    }

    function submitRedemption(OrderInfo calldata order, bytes calldata signedQuote) external {
        if (order.user != msg.sender) revert NoProxyOrders(); // TODO: should we allow beneficiary != msg.sender?
        if (!paymentToken[order.quote.paymentToken]) revert UnsupportedPaymentToken();
        address oracleAddress = ECDSA.recoverCalldata(_hashTypedData(hashQuote(order.quote)), signedQuote);
        if (!priceOracle[oracleAddress]) revert WrongPriceOracle();

        // TODO: support multiple identical orders from the same account
        bytes32 orderId = hashOrderInfo(order);
        _redemptions[orderId] = true;
        emit RedemptionSubmitted(orderId, order.user, order);

        // Move asset tokens
        // TODO: is there a more secure way than holding all this here?
        SafeTransferLib.safeTransferFrom(order.quote.assetToken, msg.sender, address(this), order.amount);
    }

    function fulfillPurchase(OrderInfo calldata order, uint256 purchasedAmount) external onlyRoles(_ROLE_1) {
        bytes32 orderId = hashOrderInfo(order);
        if (!_purchases[orderId]) revert OrderNotFound();
        // TODO: How does uniswap handle this?
        if (purchasedAmount > order.amount * (1 ether + order.maxSlippage) / 1 ether) revert SlippageLimitExceeded();

        delete _purchases[orderId];

        // Mint
        IMintBurn(order.quote.assetToken).mint(order.user, purchasedAmount);
        // Claim payment
        uint256 paymentAmount = order.amount * order.quote.price;
        SafeTransferLib.safeTransfer(order.quote.paymentToken, msg.sender, paymentAmount);
    }

    function fulfillRedemption(OrderInfo calldata order, uint256 proceeds) external onlyRoles(_ROLE_1) {
        bytes32 orderId = hashOrderInfo(order);
        if (!_redemptions[orderId]) revert OrderNotFound();
        // TODO: How does uniswap handle this?
        uint256 quoteValue = order.amount * order.quote.price;
        if (proceeds < quoteValue * (1 ether - order.maxSlippage) / 1 ether) revert SlippageLimitExceeded();

        delete _redemptions[orderId];

        // Forward payment
        SafeTransferLib.safeTransferFrom(order.quote.paymentToken, msg.sender, order.user, proceeds);
        // Burn
        IMintBurn(order.quote.assetToken).burn(order.amount);
    }

    function _domainNameAndVersion()
        internal
        pure
        virtual
        override
        returns (string memory name, string memory version)
    {
        return ("Bridge", "1");
    }
}
