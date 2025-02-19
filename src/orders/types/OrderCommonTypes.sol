// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {IDShareFactory} from "../../IDShareFactory.sol";

library OrderCommonTypes {
    // Market or limit order
    enum OrderType {
        MARKET,
        LIMIT
    }

    // Time in force
    enum TIF {
        // Good until end of day
        DAY,
        // Good until cancelled
        GTC,
        // Immediate or cancel
        IOC,
        // Fill or kill
        FOK
    }

    // Order status enum
    enum OrderStatus {
        // Order has never existed
        NONE,
        // Order is active
        ACTIVE,
        // Order is completely filled
        FULFILLED,
        // Order is cancelled
        CANCELLED
    }

    struct Order {
        // Timestamp or other salt added to order hash for replay protection
        uint64 requestTimestamp;
        // Recipient of order fills
        address recipient;
        // Bridged asset token
        address assetToken;
        // Payment token
        address paymentToken;
        // Buy or sell
        bool sell;
        // Market or limit
        OrderType orderType;
        // Amount of asset token to be used for fills
        uint256 assetTokenQuantity;
        // Amount of payment token to be used for fills
        uint256 paymentTokenQuantity;
        // Price for limit orders in ether decimals
        uint256 price;
        // Time in force
        TIF tif;
    }

    struct PricePoint {
        // Price specified with 18 decimals
        uint256 price;
        uint64 blocktime;
    }

    struct OrderState {
        // Account that requested the order
        address requester;
        // Amount of order token remaining to be used
        uint256 unfilledAmount;
        // Buy order fees escrowed
        uint256 feesEscrowed;
        // Cumulative fees taken for order
        uint256 feesTaken;
        // Amount of token received from fills
        uint256 receivedAmount;
    }

    struct PaymentTokenConfig {
        bool enabled;
        // Assumes token decimals do not change
        uint8 decimals;
        // Token blacklist method selectors
        bytes4 blacklistCallSelector;
        // Standard fee schedule per paymentToken
        uint64 perOrderFeeBuy;
        uint24 percentageFeeRateBuy;
        uint64 perOrderFeeSell;
        uint24 percentageFeeRateSell;
    }

    struct OrderProcessorStorage {
        // Address to receive fees
        address _treasury;
        // Address of payment vault
        address _vault;
        // DShareFactory contract
        IDShareFactory _dShareFactory;
        // Are orders paused?
        bool _ordersPaused;
        // Operators for filling and cancelling orders
        mapping(address => bool) _operators;
        // Status of order
        mapping(uint256 => OrderStatus) _status;
        // Active order state
        mapping(uint256 => OrderState) _orders;
        // Reduction of order decimals for asset token, defaults to 0
        mapping(address => uint8) _orderDecimalReduction;
        // Payment token configuration data
        mapping(address => PaymentTokenConfig) _paymentTokens;
        // Latest pairwise price
        mapping(bytes32 => PricePoint) _latestFillPrice;
    }

    struct Signature {
        uint64 deadline;
        bytes signature;
    }

    struct FeeQuote {
        uint256 orderId;
        address requester;
        uint256 fee;
        uint64 timestamp;
        uint64 deadline;
    }
}
