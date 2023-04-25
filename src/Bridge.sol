// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solady/auth/Ownable.sol";
import "solady/utils/ECDSA.sol";
import "solady/utils/EIP712.sol";
import "./IMintBurn.sol";

/// @notice Bridge interface managing swaps for bridged assets
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/Bridge.sol)
contract Bridge is Ownable, EIP712 {
    // This contract handles the submission and fulfillment of orders
    // forwarder/gsn support?
    // TODO: upgradeable, pausable
    // TODO: one bridge per token, or per network?
    // How do bridges maintain quotes and slippage checks?
    // Is "emit the data, store the hash" useful anywhere - see synapse

    // 1. Order submitted and payment escrowed
    // 2. Order fulfilled and escrow claimed
    // 2a. If order failed, escrow released

    enum OrderType {
        MarketBuy,
        MarketSell
    }

    struct Quote {
        address assetToken;
        address paymentToken;
        OrderType orderType;
        uint32 blockNumber; // change to time if needed
        uint224 value;
    }

    struct OrderInfo {
        address user;
        Quote quote;
        uint256 amount;
        uint256 maxSlippage;
    }

    // need to check
    struct OrderQueueItem {
        bytes32 orderHash;
        address user;
    }

    error UnsupportedPaymentToken();
    error WrongPriceOracle();
    error NoProxyOrders();

    event PaymentTokenSet(address indexed token, bool enabled);
    event PriceOracleSet(address indexed oracle, bool enabled);
    event OrderSubmitted(bytes32 indexed orderId, address indexed user, OrderInfo orderInfo);

    // keccak256(Quote(...))
    bytes32 public constant QUOTE_TYPE_HASH = 0x31e18914af06536093e4f10eacf2b0786b453f931f48b7261720891bd095dfd5;
    // keccak256(OrderInfo(...))
    bytes32 public constant ORDER_TYPE_HASH = 0xd4013e278d836a716378026f9f053fbb79270a50d5c47537840adcaaf86b3b30;

    /// @dev How long a quote is valid in blocks
    uint32 public quoteDuration;

    uint256 public defaultMaxSlippage;

    /// @dev accepted payment tokens for this issuer
    mapping(address => bool) public paymentToken;

    /// @dev trusted oracles for this issuer
    mapping(address => bool) public priceOracle;

    /// @dev unfulfilled orders
    // TODO: make collection efficient
    // TODO: need beneficiary account and price info
    // TODO: generalize order queuing across order types? support limit in future?
    // TODO: consider time received?
    mapping(bytes32 => bool) private _orders;

    // per block quote (price, time)
    // - can this be a pass-through calldata quote signed by our oracle? then we can serve from out API and save gas
    // - check how quotes currently work in bridges etc.
    // max slippage
    // amount
    constructor(uint32 quoteDuration_, uint256 defaultMaxSlippage_) {
        quoteDuration = quoteDuration_;
        defaultMaxSlippage = defaultMaxSlippage_;
    }

    function isOrderActive(bytes32 orderId) external view returns (bool) {
        return _orders[orderId];
    }

    function hashQuote(Quote memory quote) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPE_HASH, quote.assetToken, quote.paymentToken, quote.orderType, quote.blockNumber, quote.value
            )
        );
    }

    function hashOrderInfo(OrderInfo memory orderInfo) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                QUOTE_TYPE_HASH,
                orderInfo.user,
                orderInfo.quote.assetToken,
                orderInfo.quote.paymentToken,
                orderInfo.quote.orderType,
                orderInfo.quote.blockNumber,
                orderInfo.quote.value,
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

    function submitOrder(OrderInfo calldata order, bytes calldata signedQuote) external {
        if (order.user != msg.sender) revert NoProxyOrders(); // TODO: should we allow beneficiary != msg.sender?
        if (!paymentToken[order.quote.paymentToken]) revert UnsupportedPaymentToken();
        bytes32 orderId = hashQuote(order.quote);
        address oracleAddress = ECDSA.recoverCalldata(_hashTypedData(orderId), signedQuote);
        if (!priceOracle[oracleAddress]) revert WrongPriceOracle();

        _orders[orderId] = true;
        emit OrderSubmitted(orderId, order.user, order);

        // Move payment tokens
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
