// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {
    UUPSUpgradeable,
    Initializable
} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {EIP712Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/cryptography/EIP712Upgradeable.sol";
import {MulticallUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/MulticallUpgradeable.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {mulDiv, mulDiv18} from "prb-math/Common.sol";
import {SelfPermit} from "../common/SelfPermit.sol";
import {IOrderProcessor} from "./IOrderProcessor.sol";
import {IDShare} from "../IDShare.sol";
import {FeeLib} from "../common/FeeLib.sol";
import {OracleLib} from "../common/OracleLib.sol";
import {IDShareFactory} from "../IDShareFactory.sol";

/// @notice Core contract managing orders for dShare tokens
/// @dev Assumes dShare asset tokens have 18 decimals and payment tokens have .decimals()
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/orders/OrderProcessor.sol)
contract OrderProcessor is
    Initializable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    EIP712Upgradeable,
    MulticallUpgradeable,
    SelfPermit,
    IOrderProcessor
{
    using SafeERC20 for IERC20;
    using Address for address;

    /// ------------------ Types ------------------ ///

    // Order state cleared after order is fulfilled or cancelled.
    struct OrderState {
        // Account that requested the order
        address requester;
        // Amount of order token remaining to be used
        uint256 unfilledAmount;
        // Buy order fees escrowed
        uint256 feesEscrowed;
    }

    struct PaymentTokenConfig {
        bool enabled;
        uint8 decimals;
        // Token blacklist method selectors
        bytes4 blacklistCallSelector;
        // Standard fee schedule per paymentToken
        uint64 perOrderFeeBuy;
        uint24 percentageFeeRateBuy;
        uint64 perOrderFeeSell;
        uint24 percentageFeeRateSell;
    }

    /// @dev Signature deadline expired
    error ExpiredSignature();
    /// @dev Zero address
    error ZeroAddress();
    /// @dev Orders are paused
    error Paused();
    /// @dev Zero value
    error ZeroValue();
    /// @dev Order does not exist
    error OrderNotFound();
    error ExistingOrder();
    /// @dev Amount too large
    error AmountTooLarge();
    error UnsupportedToken(address token);
    /// @dev blacklist address
    error Blacklist();
    /// @dev Thrown when assetTokenQuantity's precision doesn't match the expected precision in orderDecimals.
    error InvalidPrecision();
    error LimitPriceNotSet();
    error OrderFillBelowLimitPrice();
    error OrderFillAboveLimitPrice();
    error NotOperator();
    error NotRequester();

    /// @dev Emitted when `treasury` is set
    event TreasurySet(address indexed treasury);
    /// @dev Emitted when `vault` is set
    event VaultSet(address indexed vault);
    /// @dev Emitted when orders are paused/unpaused
    event OrdersPaused(bool paused);
    event PaymentTokenSet(
        address indexed paymentToken,
        bytes4 blacklistCallSelector,
        uint64 perOrderFeeBuy,
        uint24 percentageFeeRateBuy,
        uint64 perOrderFeeSell,
        uint24 percentageFeeRateSell
    );
    event PaymentTokenRemoved(address indexed paymentToken);
    event OrderDecimalReductionSet(address indexed assetToken, uint8 decimalReduction);
    event OperatorSet(address indexed account, bool status);

    /// ------------------ Constants ------------------ ///

    bytes32 private constant ORDER_TYPEHASH = keccak256(
        "Order(uint64 requestTimestamp,address recipient,address assetToken,address paymentToken,bool sell,uint8 orderType,uint256 assetTokenQuantity,uint256 paymentTokenQuantity,uint256 price,uint8 tif)"
    );

    bytes32 private constant ORDER_REQUEST_TYPEHASH = keccak256("OrderRequest(uint256 id,uint256 deadline)");

    /// ------------------ State ------------------ ///

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
        // Reduciton of order decimals for asset token, defaults to 0
        mapping(address => uint8) _orderDecimalReduction;
        // Payment token configuration data
        mapping(address => PaymentTokenConfig) _paymentTokens;
        // Latest pairwise price
        mapping(bytes32 => PricePoint) _latestFillPrice;
    }

    // keccak256(abi.encode(uint256(keccak256("dinaricrypto.storage.OrderProcessor")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OrderProcessorStorageLocation =
        0x8036d9ca2814a3bcd78d3e8aba96b71e7697006bd322a98e7f5f0f41b09a8b00;

    function _getOrderProcessorStorage() private pure returns (OrderProcessorStorage storage $) {
        assembly {
            $.slot := OrderProcessorStorageLocation
        }
    }

    /// ------------------ Initialization ------------------ ///

    /// @notice Initialize contract
    /// @param _owner Owner of contract
    /// @param _treasury Address to receive fees
    /// @param _vault Address of vault contract
    /// @param _dShareFactory DShareFactory contract
    /// @dev Treasury cannot be zero address
    function initialize(address _owner, address _treasury, address _vault, IDShareFactory _dShareFactory)
        public
        virtual
        initializer
    {
        __Ownable_init(_owner);
        __EIP712_init("OrderProcessor", "1");
        __Multicall_init();

        // Don't send fees to zero address
        if (_treasury == address(0)) revert ZeroAddress();
        if (_vault == address(0)) revert ZeroAddress();
        if (address(_dShareFactory) == address(0)) revert ZeroAddress();

        // Initialize
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._treasury = _treasury;
        $._vault = _vault;
        $._dShareFactory = _dShareFactory;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// ------------------ Getters ------------------ ///

    /// @notice Address to receive fees
    function treasury() external view returns (address) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._treasury;
    }

    /// @notice Address of vault contract
    function vault() external view returns (address) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._vault;
    }

    /// @notice DShareFactory contract
    function dShareFactory() external view returns (IDShareFactory) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._dShareFactory;
    }

    /// @notice Are orders paused?
    function ordersPaused() external view returns (bool) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._ordersPaused;
    }

    function isOperator(address account) external view returns (bool) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._operators[account];
    }

    /// @inheritdoc IOrderProcessor
    function getOrderStatus(uint256 id) external view returns (OrderStatus) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._status[id];
    }

    /// @inheritdoc IOrderProcessor
    function getUnfilledAmount(uint256 id) external view returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._orders[id].unfilledAmount;
    }

    /// @inheritdoc IOrderProcessor
    function getFeesEscrowed(uint256 id) external view returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._orders[id].feesEscrowed;
    }

    /// @inheritdoc IOrderProcessor
    function orderDecimalReduction(address token) external view override returns (uint8) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._orderDecimalReduction[token];
    }

    function getPaymentTokenConfig(address paymentToken) public view returns (PaymentTokenConfig memory) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._paymentTokens[paymentToken];
    }

    /// @inheritdoc IOrderProcessor
    function getStandardFees(bool sell, address paymentToken) external view returns (uint256, uint24) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        PaymentTokenConfig memory paymentTokenConfig = $._paymentTokens[paymentToken];
        if (!paymentTokenConfig.enabled) revert UnsupportedToken(paymentToken);
        if (sell) {
            return (
                FeeLib.flatFeeForOrder(paymentTokenConfig.decimals, paymentTokenConfig.perOrderFeeSell),
                paymentTokenConfig.percentageFeeRateSell
            );
        } else {
            return (
                FeeLib.flatFeeForOrder(paymentTokenConfig.decimals, paymentTokenConfig.perOrderFeeBuy),
                paymentTokenConfig.percentageFeeRateBuy
            );
        }
    }

    function isTransferLocked(address token, address account) external view returns (bool) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        bytes4 selector = $._paymentTokens[token].blacklistCallSelector;
        // if no selector is set, default to locked == false
        if (selector == 0) return false;

        return _checkTransferLocked(token, account, selector);
    }

    function _checkTransferLocked(address token, address account, bytes4 selector) internal view returns (bool) {
        // assumes bool result
        return abi.decode(token.functionStaticCall(abi.encodeWithSelector(selector, account)), (bool));
    }

    function latestFillPrice(address assetToken, address paymentToken) external view returns (PricePoint memory) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._latestFillPrice[OracleLib.pairIndex(assetToken, paymentToken)];
    }

    // slither-disable-next-line naming-convention
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// ------------------ Administration ------------------ ///

    /// @dev Check if orders are paused
    modifier whenOrdersNotPaused() {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        if ($._ordersPaused) revert Paused();
        _;
    }

    modifier onlyOperator() {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        if (!$._operators[msg.sender]) revert NotOperator();
        _;
    }

    /// @notice Set treasury address
    /// @param account Address to receive fees
    /// @dev Only callable by admin
    /// Treasury cannot be zero address
    function setTreasury(address account) external onlyOwner {
        // Don't send fees to zero address
        if (account == address(0)) revert ZeroAddress();

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._treasury = account;
        emit TreasurySet(account);
    }

    /// @notice Set vault address
    /// @param account Address of vault contract
    /// @dev Only callable by admin
    /// Vault cannot be zero address
    function setVault(address account) external onlyOwner {
        // Don't send tokens to zero address
        if (account == address(0)) revert ZeroAddress();

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._vault = account;
        emit VaultSet(account);
    }

    /// @notice Pause/unpause orders
    /// @param pause Pause orders if true, unpause if false
    /// @dev Only callable by admin
    function setOrdersPaused(bool pause) external onlyOwner {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._ordersPaused = pause;
        emit OrdersPaused(pause);
    }

    /// @notice Set operator
    /// @param account Operator address
    /// @param status Operator status
    /// @dev Only callable by admin
    function setOperator(address account, bool status) external onlyOwner {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._operators[account] = status;
        emit OperatorSet(account, status);
    }

    /// @notice Set payment token configuration information
    /// @param paymentToken Payment token address
    /// @param blacklistCallSelector Method selector for blacklist check
    /// @param perOrderFeeBuy Flat fee for buy orders
    /// @param percentageFeeRateBuy Percentage fee rate for buy orders
    /// @param perOrderFeeSell Flat fee for sell orders
    /// @param percentageFeeRateSell Percentage fee rate for sell orders
    /// @dev Only callable by admin
    function setPaymentToken(
        address paymentToken,
        bytes4 blacklistCallSelector,
        uint64 perOrderFeeBuy,
        uint24 percentageFeeRateBuy,
        uint64 perOrderFeeSell,
        uint24 percentageFeeRateSell
    ) external onlyOwner {
        FeeLib.checkPercentageFeeRate(percentageFeeRateBuy);
        FeeLib.checkPercentageFeeRate(percentageFeeRateSell);
        // Token contract must implement the selector, if specified
        if (blacklistCallSelector != 0) _checkTransferLocked(paymentToken, address(this), blacklistCallSelector);

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._paymentTokens[paymentToken] = PaymentTokenConfig({
            enabled: true,
            decimals: IERC20Metadata(paymentToken).decimals(),
            blacklistCallSelector: blacklistCallSelector,
            perOrderFeeBuy: perOrderFeeBuy,
            percentageFeeRateBuy: percentageFeeRateBuy,
            perOrderFeeSell: perOrderFeeSell,
            percentageFeeRateSell: percentageFeeRateSell
        });
        emit PaymentTokenSet(
            paymentToken,
            blacklistCallSelector,
            perOrderFeeBuy,
            percentageFeeRateBuy,
            perOrderFeeSell,
            percentageFeeRateSell
        );
    }

    /// @notice Remove payment token configuration
    /// @param paymentToken Payment token address
    /// @dev Only callable by admin
    function removePaymentToken(address paymentToken) external onlyOwner {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        delete $._paymentTokens[paymentToken];
        emit PaymentTokenRemoved(paymentToken);
    }

    /// @notice Set the order decimal reduction for asset token
    /// @param token Asset token
    /// @param decimalReduction Reduces the max precision of the asset token quantity
    /// @dev Only callable by admin
    function setOrderDecimalReduction(address token, uint8 decimalReduction) external onlyOwner {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._orderDecimalReduction[token] = decimalReduction;
        emit OrderDecimalReductionSet(token, decimalReduction);
    }

    /// ------------------ Order Lifecycle ------------------ ///

    /// @inheritdoc IOrderProcessor
    function createOrderWithSignature(Order calldata order, Signature calldata signature)
        external
        whenOrdersNotPaused
        onlyOperator
        returns (uint256 id)
    {
        // Recover requester and validate signature
        if (signature.deadline < block.timestamp) revert ExpiredSignature();
        address requester =
            ECDSA.recover(_hashTypedDataV4(hashOrderRequest(order, signature.deadline)), signature.signature);

        // Create order
        return _createOrder(order, requester);
    }

    /// @dev Validate order, initialize order state, and pull tokens
    // slither-disable-next-line cyclomatic-complexity
    function _createOrder(Order calldata order, address requester) private returns (uint256 id) {
        // ------------------ Checks ------------------ //

        // Cheap checks first
        if (order.recipient == address(0)) revert ZeroAddress();
        uint256 orderAmount = (order.sell) ? order.assetTokenQuantity : order.paymentTokenQuantity;
        // No zero orders
        if (orderAmount == 0) revert ZeroValue();
        // Ensure that price is set for limit orders
        if (order.orderType == OrderType.LIMIT && order.price == 0) revert LimitPriceNotSet();

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();

        // Order must not have existed
        id = hashOrder(order);
        if ($._status[id] != OrderStatus.NONE) revert ExistingOrder();

        // Check for whitelisted tokens
        if (!$._dShareFactory.isTokenDShare(order.assetToken)) revert UnsupportedToken(order.assetToken);
        PaymentTokenConfig memory paymentTokenConfig = $._paymentTokens[order.paymentToken];
        if (!paymentTokenConfig.enabled) revert UnsupportedToken(order.paymentToken);

        // Precision checked for assetTokenQuantity, market buys excluded
        if (order.sell || order.orderType == OrderType.LIMIT) {
            uint8 decimalReduction = $._orderDecimalReduction[order.assetToken];
            if (decimalReduction > 0 && (order.assetTokenQuantity % 10 ** (decimalReduction - 1)) != 0) {
                revert InvalidPrecision();
            }
        }

        // Black list checker, assumes asset tokens are dShares
        if (
            IDShare(order.assetToken).isBlacklisted(order.recipient)
                || IDShare(order.assetToken).isBlacklisted(requester)
                || _checkTransferLocked(order.paymentToken, order.recipient, paymentTokenConfig.blacklistCallSelector)
                || _checkTransferLocked(order.paymentToken, requester, paymentTokenConfig.blacklistCallSelector)
        ) revert Blacklist();

        // Calculate fee escrow due now for buy orders
        uint256 feesEscrowed = 0;
        if (!order.sell) {
            feesEscrowed = FeeLib.flatFeeForOrder(paymentTokenConfig.decimals, paymentTokenConfig.perOrderFeeBuy)
                + FeeLib.applyPercentageFee(paymentTokenConfig.percentageFeeRateBuy, order.paymentTokenQuantity);
        }

        // ------------------ Effects ------------------ //

        // Initialize order state
        $._orders[id] = OrderState({requester: requester, unfilledAmount: orderAmount, feesEscrowed: feesEscrowed});
        $._status[id] = OrderStatus.ACTIVE;

        emit OrderCreated(id, requester, order);

        // ------------------ Interactions ------------------ //

        // Move funds to vault for buys, burn assets for sells
        if (order.sell) {
            // Burn asset
            IDShare(order.assetToken).burnFrom(requester, order.assetTokenQuantity);
        } else {
            // Sweep payment for purchase
            IERC20(order.paymentToken).safeTransferFrom(requester, $._vault, order.paymentTokenQuantity);
            // Escrow fees
            IERC20(order.paymentToken).safeTransferFrom(requester, address(this), feesEscrowed);
        }
    }

    /// @inheritdoc IOrderProcessor
    function requestOrder(Order calldata order) external whenOrdersNotPaused returns (uint256 id) {
        return _createOrder(order, msg.sender);
    }

    function hashOrderRequest(Order calldata order, uint256 deadline) public pure returns (bytes32) {
        return keccak256(abi.encode(ORDER_REQUEST_TYPEHASH, hashOrder(order), deadline));
    }

    /// @inheritdoc IOrderProcessor
    function hashOrder(Order calldata order) public pure returns (uint256) {
        return uint256(
            keccak256(
                abi.encode(
                    ORDER_TYPEHASH,
                    order.requestTimestamp,
                    order.recipient,
                    order.assetToken,
                    order.paymentToken,
                    order.sell,
                    order.orderType,
                    order.assetTokenQuantity,
                    order.paymentTokenQuantity,
                    order.price,
                    order.tif
                )
            )
        );
    }

    /// @inheritdoc IOrderProcessor
    // slither-disable-next-line cyclomatic-complexity
    function fillOrder(Order calldata order, uint256 fillAmount, uint256 receivedAmount, uint256 fees)
        external
        onlyOperator
    {
        // ------------------ Checks ------------------ //

        // No nonsense
        if (fillAmount == 0) revert ZeroValue();
        // Order ID
        uint256 id = hashOrder(order);

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        OrderState memory orderState = $._orders[id];

        // Order must exist
        if (orderState.requester == address(0)) revert OrderNotFound();
        // Fill cannot exceed remaining order
        if (fillAmount > orderState.unfilledAmount) revert AmountTooLarge();

        uint256 assetAmount;
        uint256 paymentAmount;
        uint256 remainingFeesEscrowed = 0;
        if (order.sell) {
            // Fees cannot exceed proceeds
            if (fees > receivedAmount) revert AmountTooLarge();
            // For limit sell orders, ensure that the received amount is greater or equal to limit price * fill amount, order price has ether decimals
            if (order.orderType == OrderType.LIMIT && receivedAmount < mulDiv18(fillAmount, order.price)) {
                revert OrderFillAboveLimitPrice();
            }
            assetAmount = fillAmount;
            paymentAmount = receivedAmount;
        } else {
            // Fees cannot exceed remaining deposit
            if (fees > orderState.feesEscrowed) revert AmountTooLarge();
            // For limit buy orders, ensure that the received amount is greater or equal to fill amount / limit price, order price has ether decimals
            if (order.orderType == OrderType.LIMIT && receivedAmount < mulDiv(fillAmount, 1 ether, order.price)) {
                revert OrderFillBelowLimitPrice();
            }
            assetAmount = receivedAmount;
            paymentAmount = fillAmount;
            remainingFeesEscrowed = orderState.feesEscrowed - fees;
        }

        // ------------------ Effects ------------------ //

        // Update price oracle
        bytes32 pairIndex = OracleLib.pairIndex(order.assetToken, order.paymentToken);
        $._latestFillPrice[pairIndex] = PricePoint({
            blocktime: uint64(block.timestamp),
            price: order.orderType == OrderType.LIMIT
                ? order.price
                : OracleLib.calculatePrice(assetAmount, paymentAmount, $._paymentTokens[order.paymentToken].decimals)
        });

        // Notify order filled
        emit OrderFill(
            id, order.paymentToken, order.assetToken, orderState.requester, assetAmount, paymentAmount, fees, order.sell
        );

        // Update order state
        uint256 newUnfilledAmount = orderState.unfilledAmount - fillAmount;
        // If order is completely filled then clear order state
        if (newUnfilledAmount == 0) {
            $._status[id] = OrderStatus.FULFILLED;
            // Clear order state
            delete $._orders[id];
            // Notify order fulfilled
            emit OrderFulfilled(id, orderState.requester);
            // Refund remaining fees
            if (remainingFeesEscrowed > 0) {
                // Interaction
                IERC20(order.paymentToken).safeTransfer(orderState.requester, remainingFeesEscrowed);
            }
        } else {
            // Otherwise update order state
            $._orders[id].unfilledAmount = newUnfilledAmount;
            if (!order.sell) {
                $._orders[id].feesEscrowed = remainingFeesEscrowed;
            }
        }

        // ------------------ Interactions ------------------ //

        // Move funds from operator for sells, mint assets for buys
        if (order.sell) {
            // Transfer the received amount from the filler to this contract
            IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), receivedAmount);

            // If there are proceeds from the order, transfer them to the recipient
            uint256 paymentEarned = receivedAmount - fees;
            if (paymentEarned > 0) {
                IERC20(order.paymentToken).safeTransfer(order.recipient, paymentEarned);
            }
        } else {
            // Mint asset
            IDShare(order.assetToken).mint(order.recipient, receivedAmount);
        }

        // If there are protocol fees from the order, transfer them to the treasury
        if (fees > 0) {
            IERC20(order.paymentToken).safeTransfer($._treasury, fees);
        }
    }

    /// @inheritdoc IOrderProcessor
    function requestCancel(uint256 id) external {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        // Order must exist
        address requester = $._orders[id].requester;
        if (requester == address(0)) revert OrderNotFound();
        // Only requester can request cancellation
        if (requester != msg.sender) revert NotRequester();

        // Send cancel request to bridge
        emit CancelRequested(id, requester);
    }

    /// @inheritdoc IOrderProcessor
    function cancelOrder(Order calldata order, string calldata reason) external onlyOperator {
        // ------------------ Checks ------------------ //

        // Order ID
        uint256 id = hashOrder(order);

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        OrderState storage orderState = $._orders[id];
        address requester = orderState.requester;
        // Order must exist
        if (requester == address(0)) revert OrderNotFound();

        // ------------------ Effects ------------------ //

        // If buy order, then refund fee deposit
        uint256 feeRefund = order.sell ? 0 : orderState.feesEscrowed;
        uint256 unfilledAmount = orderState.unfilledAmount;

        // Order is cancelled
        $._status[id] = OrderStatus.CANCELLED;

        // Clear order state
        delete $._orders[id];

        // Notify order cancelled
        emit OrderCancelled(id, requester, reason);

        // ------------------ Interactions ------------------ //

        // Return escrowed fees and unfilled amount
        if (order.sell) {
            // Mint unfilled
            IDShare(order.assetToken).mint(requester, unfilledAmount);
        } else {
            // Return unfilled
            IERC20(order.paymentToken).safeTransferFrom(msg.sender, requester, unfilledAmount);
            if (feeRefund > 0) {
                IERC20(order.paymentToken).safeTransfer(requester, feeRefund);
            }
        }
    }
}
