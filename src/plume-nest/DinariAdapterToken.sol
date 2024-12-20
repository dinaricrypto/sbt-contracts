// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {ComponentToken, IERC7540} from "plume-contracts/nest/src/ComponentToken.sol";
import {IComponentToken} from "plume-contracts/nest/src/interfaces/IComponentToken.sol";
import {IOrderProcessor} from "../orders/IOrderProcessor.sol";
import {OracleLib} from "../common/OracleLib.sol";
import {FeeLib} from "../common/FeeLib.sol";

/**
 * @title DinariAdapterToken
 * @author Jake Timothy, Eugene Y. Q. Shen
 * @notice Implementation of the abstract ComponentToken that interfaces with external assets.
 * @dev Asset is USDC. Holds wrapped dShares to accumulate yield.
 */
contract DinariAdapterToken is ComponentToken {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    uint64 private constant PRICE_STALE_DURATION = 1 days;

    // Storage

    struct DShareOrderInfo {
        bool sell;
        uint256 orderAmount;
        uint256 fees;
    }

    /// @custom:storage-location erc7201:plume.storage.DinariAdapterToken
    struct DinariAdapterTokenStorage {
        /// @dev dShare token underlying component token
        address dshareToken;
        /// @dev Wrapped dShare token underlying component token
        address wrappedDshareToken;
        /// @dev Address of the Nest Staking contract
        address nestStakingContract;
        /// @dev Address of the dShares order contract
        IOrderProcessor externalOrderContract;
        /// @dev Submitted order information
        mapping(uint256 orderId => DShareOrderInfo) submittedOrderInfo;
        /// @dev Submitted order queue
        DoubleEndedQueue.Bytes32Deque submittedOrders;
        /// @dev Order nonce
        uint64 orderNonce;
        /// @dev Oracle price stale duration
        uint64 priceStaleDuration;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.DinariAdapterToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DINARI_ADAPTER_TOKEN_STORAGE_LOCATION =
        0x2a49a1f589de6263f42d4846b2f178279aaa9b9efbd070fd2367cbda9b826400;

    function _getDinariAdapterTokenStorage() private pure returns (DinariAdapterTokenStorage storage $) {
        assembly {
            $.slot := DINARI_ADAPTER_TOKEN_STORAGE_LOCATION
        }
    }

    // Errors

    error NoOutstandingOrders();
    error OrderDoesNotExist();
    error OrderStillActive();
    error InvalidPrice();
    error StalePrice(uint64 blocktime, uint64 priceBlocktime);
    error AmountTooSmall();

    // Initializer

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the DinariAdapterToken
     * @param owner Address of the owner of the DinariAdapterToken
     * @param name Name of the DinariAdapterToken
     * @param symbol Symbol of the DinariAdapterToken
     * @param currencyToken CurrencyToken used to mint and burn the DinariAdapterToken
     * @param dshareToken dShare token underlying component token
     * @param nestStakingContract Address of the Nest Staking contract
     * @param externalOrderContract Address of the dShares order contract
     */
    function initialize(
        address owner,
        string memory name,
        string memory symbol,
        address currencyToken,
        address dshareToken,
        address wrappedDshareToken,
        address nestStakingContract,
        address externalOrderContract
    ) public initializer {
        super.initialize(owner, name, symbol, IERC20(currencyToken), true, true);
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        $.dshareToken = dshareToken;
        $.wrappedDshareToken = wrappedDshareToken;
        $.nestStakingContract = nestStakingContract;
        $.externalOrderContract = IOrderProcessor(externalOrderContract);

        $.priceStaleDuration = PRICE_STALE_DURATION;
    }

    // Override Functions

    /// @inheritdoc IComponentToken
    function convertToShares(uint256 assets) public view override(ComponentToken) returns (uint256 shares) {
        // Apply dshare price and wrapped conversion rate, fees
        // USDC -> dShares -> wrapped dShares
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        IOrderProcessor orderContract = $.externalOrderContract;
        address paymentToken = asset();
        (uint256 orderAmount, uint256 fees) = _getOrderFromTotalBuy(orderContract, paymentToken, assets);
        uint256 price = _getDSharePrice(orderContract, $.dshareToken, paymentToken);
        return IERC4626($.wrappedDshareToken).convertToShares(
            OracleLib.applyPricePaymentToAsset(orderAmount + fees, price, IERC20Metadata(paymentToken).decimals())
        );
    }

    function _getDSharePrice(IOrderProcessor orderContract, address assetToken, address paymentToken)
        private
        view
        returns (uint256 price)
    {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        IOrderProcessor.PricePoint memory pricePoint = orderContract.latestFillPrice($.dshareToken, paymentToken);
        if (pricePoint.price == 0) revert InvalidPrice();
        if (block.timestamp - pricePoint.blocktime > $.priceStaleDuration) {
            revert StalePrice(uint64(block.timestamp), pricePoint.blocktime);
        }
        return pricePoint.price;
    }

    function _getOrderFromTotalBuy(IOrderProcessor orderContract, address paymentToken, uint256 totalBuy)
        private
        view
        returns (uint256 orderAmount, uint256 fees)
    {
        // order * (1 + vfee) + flat = total
        // order = (total - flat) / (1 + vfee)
        (uint256 flatFee, uint24 percentageFeeRate) = orderContract.getStandardFees(false, paymentToken);
        if (totalBuy <= flatFee) revert AmountTooSmall();
        orderAmount = FixedPointMathLib.fullMulDiv(
            totalBuy - flatFee, FeeLib._ONEHUNDRED_PERCENT, FeeLib._ONEHUNDRED_PERCENT + percentageFeeRate
        );

        fees = orderContract.totalStandardFee(false, paymentToken, orderAmount);
    }

    /// @inheritdoc IComponentToken
    function convertToAssets(uint256 shares) public view override(ComponentToken) returns (uint256 assets) {
        // Apply wrapped conversion rate and dshare price, subtract fees
        // wrapped dShares -> dShares -> USDC
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        IOrderProcessor orderContract = $.externalOrderContract;
        address paymentToken = asset();
        address dshareToken = $.dshareToken;
        uint256 price = _getDSharePrice(orderContract, dshareToken, paymentToken);
        uint256 dshares = IERC4626($.wrappedDshareToken).convertToAssets(shares);
        uint256 orderAmount = _applyDecimalReduction(orderContract, dshareToken, dshares);
        uint256 proceeds =
            OracleLib.applyPriceAssetToPayment(orderAmount, price, IERC20Metadata(paymentToken).decimals());
        uint256 fees = orderContract.totalStandardFee(true, paymentToken, proceeds);
        if (proceeds <= fees) return 0;
        return proceeds - fees;
    }

    function _applyDecimalReduction(IOrderProcessor orderContract, address assetToken, uint256 amount)
        private
        view
        returns (uint256)
    {
        // Round down to nearest supported decimal
        uint256 precisionReductionFactor = 10 ** orderContract.orderDecimalReduction(assetToken);
        // slither-disable-next-line divide-before-multiply
        return (amount / precisionReductionFactor) * precisionReductionFactor;
    }

    /// @inheritdoc IComponentToken
    function requestDeposit(uint256 assets, address controller, address owner)
        public
        override(ComponentToken)
        returns (uint256 requestId)
    {
        // Input must be more than flat fee
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        address nestStakingContract = $.nestStakingContract;
        if (msg.sender != nestStakingContract) {
            revert Unauthorized(msg.sender, nestStakingContract);
        }

        IOrderProcessor orderContract = $.externalOrderContract;
        address paymentToken = asset();
        (uint256 orderAmount, uint256 fees) = _getOrderFromTotalBuy(orderContract, paymentToken, assets);
        uint256 totalInput = orderAmount + fees;

        // Subcall with calculated input amount to be safe
        super.requestDeposit(totalInput, controller, owner);

        // Approve payment token
        SafeTransferLib.safeApprove(paymentToken, address(orderContract), totalInput);
        // Buy
        requestId = _placeOrder(orderContract, $.dshareToken, paymentToken, orderAmount, fees, false);
    }

    function _placeOrder(
        IOrderProcessor orderContract,
        address assetToken,
        address paymentToken,
        uint256 orderAmount,
        uint256 fees,
        bool sell
    ) private returns (uint256 orderId) {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        IOrderProcessor.Order memory order = IOrderProcessor.Order({
            requestTimestamp: $.orderNonce++,
            recipient: address(this),
            assetToken: assetToken,
            paymentToken: paymentToken,
            sell: sell,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: sell ? orderAmount : 0,
            paymentTokenQuantity: sell ? 0 : orderAmount,
            price: 0,
            tif: IOrderProcessor.TIF.DAY
        });
        orderId = orderContract.createOrderStandardFees(order);
        $.submittedOrderInfo[orderId] = DShareOrderInfo({sell: sell, orderAmount: orderAmount, fees: fees});
        $.submittedOrders.pushBack(bytes32(orderId));
    }

    /// @inheritdoc IComponentToken
    function requestRedeem(uint256 shares, address controller, address owner)
        public
        override(ComponentToken)
        returns (uint256 requestId)
    {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        address nestStakingContract = $.nestStakingContract;
        if (msg.sender != nestStakingContract) {
            revert Unauthorized(msg.sender, nestStakingContract);
        }

        // Unwrap dshares
        address wrappedDshareToken = $.wrappedDshareToken;
        uint256 dshares = IERC4626(wrappedDshareToken).redeem(shares, address(this), address(this));
        // Round down to nearest supported decimal
        address dshareToken = $.dshareToken;
        IOrderProcessor orderContract = $.externalOrderContract;
        uint256 orderAmount = _applyDecimalReduction(orderContract, dshareToken, dshares);

        // Subcall with dust removed
        super.requestRedeem(orderAmount, controller, owner);

        // Rewrap dust
        uint256 dshareDust = dshares - orderAmount;
        if (dshareDust > 0) {
            // slither-disable-next-line unused-return
            IERC4626(wrappedDshareToken).deposit(dshareDust, address(this));
            // Dust shares not minted back to owner, rounded orderAmount used in requestRedeem
        }
        // Approve dshares
        SafeTransferLib.safeApprove(dshareToken, address(orderContract), orderAmount);
        // Sell
        requestId = _placeOrder(orderContract, dshareToken, asset(), orderAmount, 0, true);
    }

    function getSubmittedOrderInfo(uint256 orderId)
        public
        view
        returns (bool sell, uint256 orderAmount, uint256 fees)
    {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        DShareOrderInfo memory orderInfo = $.submittedOrderInfo[orderId];
        return (orderInfo.sell, orderInfo.orderAmount, orderInfo.fees);
    }

    function getNextSubmittedOrder() public view returns (uint256) {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        if ($.submittedOrders.length() == 0) {
            revert NoOutstandingOrders();
        }
        return uint256($.submittedOrders.front());
    }

    function processSubmittedOrders() public {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();

        DoubleEndedQueue.Bytes32Deque storage orders = $.submittedOrders;
        while (orders.length() > 0) {
            uint256 orderId = uint256(orders.front());

            IOrderProcessor.OrderStatus status = _processOrder(orderId);
            if (status == IOrderProcessor.OrderStatus.ACTIVE) {
                break;
            }

            // slither-disable-next-line unused-return
            orders.popFront();
        }
    }

    function _processOrder(uint256 orderId) private returns (IOrderProcessor.OrderStatus status) {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();

        IOrderProcessor orderContract = $.externalOrderContract;
        status = orderContract.getOrderStatus(orderId);
        if (status == IOrderProcessor.OrderStatus.ACTIVE) {
            return status;
        } else if (status == IOrderProcessor.OrderStatus.NONE) {
            revert OrderDoesNotExist();
        }

        address nestStakingContract = $.nestStakingContract;
        DShareOrderInfo memory orderInfo = $.submittedOrderInfo[orderId];
        uint256 totalInput = orderInfo.orderAmount + orderInfo.fees;

        if (status == IOrderProcessor.OrderStatus.CANCELLED) {
            // Assets have been refunded
            _getComponentTokenStorage().pendingDepositRequest[nestStakingContract] -= totalInput;
        } else if (status == IOrderProcessor.OrderStatus.FULFILLED) {
            uint256 proceeds = orderContract.getReceivedAmount(orderId);

            if (orderInfo.sell) {
                uint256 feesTaken = orderContract.getFeesTaken(orderId);
                super._notifyRedeem(proceeds - feesTaken, orderInfo.orderAmount, nestStakingContract);
            } else {
                // Wrap dshares
                address wrappedDshareToken = $.wrappedDshareToken;
                SafeTransferLib.safeApprove($.dshareToken, wrappedDshareToken, proceeds);
                uint256 shares = IERC4626(wrappedDshareToken).deposit(proceeds, address(this));

                super._notifyDeposit(totalInput, shares, nestStakingContract);

                // Send fee refund to controller
                uint256 totalSpent = orderInfo.orderAmount + orderContract.getFeesTaken(orderId);
                uint256 refund = totalInput - totalSpent;
                if (refund > 0) {
                    SafeTransferLib.safeTransfer(asset(), nestStakingContract, refund);
                }
            }
        }
    }

    /// @dev Single order processing if gas limit is reached
    function processNextSubmittedOrder() public {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();

        DoubleEndedQueue.Bytes32Deque storage orders = $.submittedOrders;
        if (orders.length() == 0) {
            revert NoOutstandingOrders();
        }
        uint256 orderId = uint256(orders.front());
        IOrderProcessor.OrderStatus status = _processOrder(orderId);
        if (status == IOrderProcessor.OrderStatus.ACTIVE) {
            revert OrderStillActive();
        }

        // slither-disable-next-line unused-return
        orders.popFront();
    }

    /// @inheritdoc IComponentToken
    function deposit(uint256 assets, address receiver, address controller)
        public
        override(ComponentToken)
        returns (uint256 shares)
    {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        address nestStakingContract = $.nestStakingContract;
        if (receiver != nestStakingContract) {
            revert Unauthorized(receiver, nestStakingContract);
        }
        return super.deposit(assets, receiver, controller);
    }

    /// @inheritdoc IERC7540
    function mint(uint256 shares, address receiver, address controller)
        public
        override(ComponentToken)
        returns (uint256 assets)
    {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        address nestStakingContract = $.nestStakingContract;
        if (receiver != nestStakingContract) {
            revert Unauthorized(receiver, nestStakingContract);
        }
        return super.mint(shares, receiver, controller);
    }

    /// @inheritdoc IComponentToken
    function redeem(uint256 shares, address receiver, address controller)
        public
        override(ComponentToken)
        returns (uint256 assets)
    {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        address nestStakingContract = $.nestStakingContract;
        if (receiver != nestStakingContract) {
            revert Unauthorized(receiver, nestStakingContract);
        }
        return super.redeem(shares, receiver, controller);
    }

    /// @inheritdoc IERC7540
    function withdraw(uint256 assets, address receiver, address controller)
        public
        override(ComponentToken)
        returns (uint256 shares)
    {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        address nestStakingContract = $.nestStakingContract;
        if (receiver != nestStakingContract) {
            revert Unauthorized(receiver, nestStakingContract);
        }
        return super.withdraw(assets, receiver, controller);
    }
}
