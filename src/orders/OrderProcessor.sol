// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {ControlledUpgradeable} from "../deployment/ControlledUpgradeable.sol";
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
    ControlledUpgradeable,
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

    error QuoteMismatch();
    /// @dev Signature deadline expired
    error ExpiredSignature();
    /// @dev Zero address
    error ZeroAddress();
    /// @dev Orders are paused
    error Paused();
    /// @dev Zero value
    error ZeroValue();
    error OrderNotActive();
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

    bytes32 private constant ORDER_REQUEST_TYPEHASH = keccak256("OrderRequest(uint256 id,uint64 deadline)");

    bytes32 private constant FEE_QUOTE_TYPEHASH =
        keccak256("FeeQuote(uint256 orderId,address requester,uint256 fee,uint64 timestamp,uint64 deadline)");

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

    /// ------------------ Version ------------------ ///

    /// @notice Returns contract version as uint8
    function version() public pure override returns (uint8) {
        return 1;
    }

    /// @notice Returns contract version as string
    function publicVersion() public pure override returns (string memory) {
        return "1.0.0";
    }

    /// ------------------ Initialization ------------------ ///

    /// @notice Initialize contract
    /// @param _owner Owner of contract
    /// @param _upgrader Address authorized to upgrade contract
    /// @param _treasury Address to receive fees
    /// @param _vault Address of vault contract
    /// @param _dShareFactory DShareFactory contract
    /// @dev Treasury cannot be zero address
    function initialize(
        address _owner,
        address _upgrader,
        address _treasury,
        address _vault,
        IDShareFactory _dShareFactory
    ) public virtual reinitializer(version()) {
        __ControlledUpgradeable_init(_owner, _upgrader);
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

    function reinitialize(address _owner, address _upgrader) external reinitializer(version()) {
        __ControlledUpgradeable_init(_owner, _upgrader);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
    function getReceivedAmount(uint256 id) external view returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._orders[id].receivedAmount;
    }

    /// @inheritdoc IOrderProcessor
    function getFeesEscrowed(uint256 id) external view returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._orders[id].feesEscrowed;
    }

    /// @inheritdoc IOrderProcessor
    function getFeesTaken(uint256 id) external view returns (uint256) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        return $._orders[id].feesTaken;
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
    function getStandardFees(bool sell, address paymentToken) public view returns (uint256, uint24) {
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

    /// @inheritdoc IOrderProcessor
    function totalStandardFee(bool sell, address paymentToken, uint256 paymentTokenQuantity)
        public
        view
        returns (uint256)
    {
        (uint256 fee, uint24 percentageFeeRate) = getStandardFees(sell, paymentToken);
        return FeeLib.applyPercentageFee(percentageFeeRate, paymentTokenQuantity) + fee;
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

    function _checkBlacklisted(address assetToken, address paymentToken, bytes4 blacklistCallSelector, address account)
        internal
        view
    {
        // Black list checker, assumes asset tokens are dShares
        if (
            IDShare(assetToken).isBlacklisted(account)
                || (blacklistCallSelector != 0 && _checkTransferLocked(paymentToken, account, blacklistCallSelector))
        ) revert Blacklist();
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
        checkOperator(msg.sender);
        _;
    }

    function checkOperator(address account) internal view {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        if (!$._operators[account]) revert NotOperator();
    }

    /// @notice Set treasury address
    /// @param account Address to receive fees
    /// @dev Only callable by admin
    /// Treasury cannot be zero address
    function setTreasury(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
    function setVault(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Don't send tokens to zero address
        if (account == address(0)) revert ZeroAddress();

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._vault = account;
        emit VaultSet(account);
    }

    /// @notice Pause/unpause orders
    /// @param pause Pause orders if true, unpause if false
    /// @dev Only callable by admin
    function setOrdersPaused(bool pause) external onlyRole(DEFAULT_ADMIN_ROLE) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._ordersPaused = pause;
        emit OrdersPaused(pause);
    }

    /// @notice Set operator
    /// @param account Operator address
    /// @param status Operator status
    /// @dev Only callable by admin
    function setOperator(address account, bool status) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
    function removePaymentToken(address paymentToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        delete $._paymentTokens[paymentToken];
        emit PaymentTokenRemoved(paymentToken);
    }

    /// @notice Set the order decimal reduction for asset token
    /// @param token Asset token
    /// @param decimalReduction Reduces the max precision of the asset token quantity
    /// @dev Only callable by admin
    function setOrderDecimalReduction(address token, uint8 decimalReduction) external onlyRole(DEFAULT_ADMIN_ROLE) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        $._orderDecimalReduction[token] = decimalReduction;
        emit OrderDecimalReductionSet(token, decimalReduction);
    }

    /// ------------------ Order Lifecycle ------------------ ///

    /// @inheritdoc IOrderProcessor
    function createOrderWithSignature(
        Order calldata order,
        Signature calldata orderSignature,
        FeeQuote calldata feeQuote,
        bytes calldata feeQuoteSignature
    ) external whenOrdersNotPaused onlyOperator returns (uint256 id) {
        // Recover requester and validate order signature
        if (orderSignature.deadline < block.timestamp) revert ExpiredSignature();
        address requester =
            ECDSA.recover(_hashTypedDataV4(hashOrderRequest(order, orderSignature.deadline)), orderSignature.signature);

        id = hashOrder(order);
        _validateFeeQuote(id, requester, feeQuote, feeQuoteSignature);

        // Create order
        _createOrder(id, order, requester, order.sell ? 0 : feeQuote.fee);
    }

    function _validateFeeQuote(
        uint256 id,
        address requester,
        FeeQuote calldata feeQuote,
        bytes calldata feeQuoteSignature
    ) private view {
        if (feeQuote.orderId != id) revert QuoteMismatch();
        if (feeQuote.requester != requester) revert NotRequester();
        if (feeQuote.deadline < block.timestamp) revert ExpiredSignature();
        address feeQuoteSigner = ECDSA.recover(_hashTypedDataV4(hashFeeQuote(feeQuote)), feeQuoteSignature);
        checkOperator(feeQuoteSigner);
    }

    /// @dev Validate order, initialize order state, and pull tokens
    // slither-disable-next-line cyclomatic-complexity
    function _createOrder(uint256 id, Order calldata order, address requester, uint256 feesEscrowed) private {
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

        _checkBlacklisted(order.assetToken, order.paymentToken, paymentTokenConfig.blacklistCallSelector, requester);
        if (order.recipient != requester) {
            _checkBlacklisted(
                order.assetToken, order.paymentToken, paymentTokenConfig.blacklistCallSelector, order.recipient
            );
        }

        // ------------------ Effects ------------------ //

        // Initialize order state
        $._orders[id] = OrderState({
            requester: requester,
            unfilledAmount: orderAmount,
            feesEscrowed: feesEscrowed,
            feesTaken: 0,
            receivedAmount: 0
        });
        $._status[id] = OrderStatus.ACTIVE;

        emit OrderCreated(id, requester, order, feesEscrowed);

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
    function createOrder(Order calldata order, FeeQuote calldata feeQuote, bytes calldata feeQuoteSignature)
        external
        whenOrdersNotPaused
        returns (uint256 id)
    {
        id = hashOrder(order);
        _validateFeeQuote(id, msg.sender, feeQuote, feeQuoteSignature);

        // Create order
        _createOrder(id, order, msg.sender, order.sell ? 0 : feeQuote.fee);
    }

    /// @inheritdoc IOrderProcessor
    function createOrderStandardFees(Order calldata order) external whenOrdersNotPaused returns (uint256 id) {
        id = hashOrder(order);
        if (order.sell) {
            _createOrder(id, order, msg.sender, 0);
        } else {
            (uint256 flatFee, uint24 percentageFeeRate) = getStandardFees(false, order.paymentToken);
            _createOrder(
                id,
                order,
                msg.sender,
                FeeLib.applyPercentageFee(percentageFeeRate, order.paymentTokenQuantity) + flatFee
            );
        }
    }

    function hashOrderRequest(Order calldata order, uint64 deadline) public pure returns (bytes32) {
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

    function hashFeeQuote(FeeQuote calldata feeQuote) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                FEE_QUOTE_TYPEHASH,
                feeQuote.orderId,
                feeQuote.requester,
                feeQuote.fee,
                feeQuote.timestamp,
                feeQuote.deadline
            )
        );
    }

    /// @inheritdoc IOrderProcessor
    function fillOrder(Order calldata order, uint256 fillAmount, uint256 receivedAmount, uint256 fees)
        external
        onlyOperator
    {
        // No nonsense
        if (fillAmount == 0) revert ZeroValue();
        // Order ID
        uint256 id = hashOrder(order);

        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        OrderState memory orderState = $._orders[id];

        // Order must be active
        if ($._status[id] != OrderStatus.ACTIVE) revert OrderNotActive();
        // Fill cannot exceed remaining order
        if (fillAmount > orderState.unfilledAmount) revert AmountTooLarge();

        if (order.sell) {
            _fillSellOrder(id, order, orderState, fillAmount, receivedAmount, fees);
        } else {
            _fillBuyOrder(id, order, orderState, receivedAmount, fillAmount, fees);
        }

        // If there are protocol fees from the order, transfer them to the treasury
        if (fees > 0) {
            IERC20(order.paymentToken).safeTransfer($._treasury, fees);
        }
    }

    function _fillSellOrder(
        uint256 id,
        Order calldata order,
        OrderState memory orderState,
        uint256 assetAmount,
        uint256 paymentAmount,
        uint256 fees
    ) private {
        // ------------------ Checks ------------------ //

        // Fees cannot exceed proceeds
        if (fees > paymentAmount) revert AmountTooLarge();
        // For limit sell orders, ensure that the received amount is greater or equal to limit price * fill amount, order price has ether decimals
        if (order.orderType == OrderType.LIMIT && paymentAmount < mulDiv18(assetAmount, order.price)) {
            revert OrderFillAboveLimitPrice();
        }

        // ------------------ Effects ------------------ //

        _publishFill(id, orderState.requester, order, assetAmount, paymentAmount, fees);

        _updateFillState(id, orderState, assetAmount, paymentAmount, fees);

        // Transfer the received amount from the filler to this contract
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), paymentAmount);

        // If there are proceeds from the order, transfer them to the recipient
        uint256 paymentEarned = paymentAmount - fees;
        if (paymentEarned > 0) {
            IERC20(order.paymentToken).safeTransfer(order.recipient, paymentEarned);
        }
    }

    function _fillBuyOrder(
        uint256 id,
        Order calldata order,
        OrderState memory orderState,
        uint256 assetAmount,
        uint256 paymentAmount,
        uint256 fees
    ) private {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();

        // ------------------ Checks ------------------ //

        // Fees cannot exceed remaining deposit
        if (fees > orderState.feesEscrowed) revert AmountTooLarge();
        // For limit buy orders, ensure that the received amount is greater or equal to fill amount / limit price, order price has ether decimals
        if (order.orderType == OrderType.LIMIT && assetAmount < mulDiv(paymentAmount, 1 ether, order.price)) {
            revert OrderFillBelowLimitPrice();
        }

        // ------------------ Effects ------------------ //

        _publishFill(id, orderState.requester, order, assetAmount, paymentAmount, fees);

        bool fulfilled = _updateFillState(id, orderState, paymentAmount, assetAmount, fees);

        // Update fee escrow (and refund if eligible)
        uint256 remainingFeesEscrowed = orderState.feesEscrowed - fees;
        if (fulfilled) {
            // Refund remaining fees
            if (remainingFeesEscrowed > 0) {
                // Interaction
                IERC20(order.paymentToken).safeTransfer(orderState.requester, remainingFeesEscrowed);
            }
        } else {
            $._orders[id].feesEscrowed = remainingFeesEscrowed;
        }

        // Mint asset
        IDShare(order.assetToken).mint(order.recipient, assetAmount);
    }

    function _publishFill(
        uint256 id,
        address requester,
        Order calldata order,
        uint256 assetAmount,
        uint256 paymentAmount,
        uint256 fees
    ) private {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();

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
            id, order.paymentToken, order.assetToken, requester, assetAmount, paymentAmount, fees, order.sell
        );
    }

    function _updateFillState(
        uint256 id,
        OrderState memory orderState,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256 fees
    ) private returns (bool fulfilled) {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();

        // Update order state
        uint256 newUnfilledAmount = orderState.unfilledAmount - fillAmount;
        $._orders[id].unfilledAmount = newUnfilledAmount;
        $._orders[id].receivedAmount = orderState.receivedAmount + receivedAmount;
        $._orders[id].feesTaken = orderState.feesTaken + fees;
        // If order is completely filled then clear order state
        fulfilled = newUnfilledAmount == 0;
        if (fulfilled) {
            $._orders[id].feesEscrowed = 0;
            $._status[id] = OrderStatus.FULFILLED;
            // Notify order fulfilled
            emit OrderFulfilled(id, orderState.requester);
        }
    }

    /// @inheritdoc IOrderProcessor
    function requestCancel(uint256 id) external {
        OrderProcessorStorage storage $ = _getOrderProcessorStorage();
        // Order must be active
        if ($._status[id] != OrderStatus.ACTIVE) revert OrderNotActive();
        // Only requester can request cancellation
        address requester = $._orders[id].requester;
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
        // Order must be active
        if ($._status[id] != OrderStatus.ACTIVE) revert OrderNotActive();

        // ------------------ Effects ------------------ //

        // If buy order, then refund fee deposit
        OrderState storage orderState = $._orders[id];
        uint256 feeRefund = order.sell ? 0 : orderState.feesEscrowed;
        uint256 unfilledAmount = orderState.unfilledAmount;

        orderState.feesEscrowed = 0;

        // Order is cancelled
        $._status[id] = OrderStatus.CANCELLED;

        // Notify order cancelled
        address requester = orderState.requester;
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
