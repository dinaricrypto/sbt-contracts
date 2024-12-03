// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
// import {ReentrancyGuardTransientUpgradeable} from 
//     "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import {ComponentToken, IERC7540} from "plume-contracts/nest/src/ComponentToken.sol";
import {IComponentToken} from "plume-contracts/nest/src/interfaces/IComponentToken.sol";
import {IOrderProcessor} from "../orders/IOrderProcessor.sol";

/**
 * @title DinariAdapterToken
 * @author Jake Timothy, Eugene Y. Q. Shen
 * @notice Implementation of the abstract ComponentToken that interfaces with external assets.
 * @dev Asset is USDC. Holds wrapped dShares to accumulate yield.
 */
contract DinariAdapterToken is ComponentToken {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

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
        //
        mapping(uint256 orderId => DShareOrderInfo) submittedOrderInfo;
        DoubleEndedQueue.Bytes32Deque submittedOrders;
        uint64 orderNonce;
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
    }

    // Override Functions

    /// @inheritdoc IComponentToken
    function assetsOf(address owner) public view override(ComponentToken) returns (uint256 assets) {
        return convertToAssets(balanceOf(owner));
    }

    /// @inheritdoc IComponentToken
    function convertToShares(uint256 assets) public view override(ComponentToken) returns (uint256 shares) {
        // Apply dshare price and wrapped conversion rate, fees
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        IOrderProcessor orderContract = $.externalOrderContract;
        address paymentToken = asset();
        (uint256 orderAmount, uint256 fees) = _getOrderFromTotalBuy(orderContract, paymentToken, assets);
        IOrderProcessor.PricePoint memory price = orderContract.latestFillPrice($.dshareToken, paymentToken);
        return IERC4626($.wrappedDshareToken).convertToShares(((orderAmount + fees) * price.price) / 1 ether);
    }

    function _getOrderFromTotalBuy(IOrderProcessor orderContract, address paymentToken, uint256 totalBuy)
        private
        view
        returns (uint256 orderAmount, uint256 fees)
    {
        // order * (1 + vfee) + flat = total
        // order = (total - flat) / (1 + vfee)
        (uint256 flatFee, uint24 percentageFeeRate) = orderContract.getStandardFees(false, paymentToken);
        orderAmount = (totalBuy - flatFee) * 1_000_000 / (1_000_000 + percentageFeeRate);

        fees = orderContract.totalStandardFee(false, paymentToken, orderAmount);
    }

    /// @inheritdoc IComponentToken
    function convertToAssets(uint256 shares) public view override(ComponentToken) returns (uint256 assets) {
        // Apply wrapped conversion rate and dshare price, subtract fees
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        IOrderProcessor orderContract = $.externalOrderContract;
        address paymentToken = asset();
        address dshareToken = $.dshareToken;
        IOrderProcessor.PricePoint memory price = orderContract.latestFillPrice(dshareToken, paymentToken);
        uint256 dshares = IERC4626($.wrappedDshareToken).convertToAssets(shares);
        // Round down to nearest supported decimal
        uint256 precisionReductionFactor = 10 ** orderContract.orderDecimalReduction(dshareToken);
        // slither-disable-next-line divide-before-multiply
        uint256 proceeds = ((dshares / precisionReductionFactor) * precisionReductionFactor * 1 ether) / price.price;
        uint256 fees = orderContract.totalStandardFee(true, paymentToken, proceeds);
        return proceeds - fees;
    }

    /// @inheritdoc IComponentToken
    function requestDeposit(uint256 assets, address controller, address owner)
        public
        override(ComponentToken)
        nonReentrant
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

        // Approve dshares
        SafeERC20.safeIncreaseAllowance(IERC20(paymentToken), address(orderContract), totalInput);
        // Buy
        IOrderProcessor.Order memory order = IOrderProcessor.Order({
            requestTimestamp: $.orderNonce++,
            recipient: address(this),
            assetToken: $.dshareToken,
            paymentToken: paymentToken,
            sell: false,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: orderAmount,
            price: 0,
            tif: IOrderProcessor.TIF.DAY
        });
        requestId = orderContract.createOrderStandardFees(order);
        $.submittedOrderInfo[requestId] = DShareOrderInfo({sell: false, orderAmount: orderAmount, fees: fees});
        $.submittedOrders.pushBack(bytes32(requestId));
    }

    /// @inheritdoc IComponentToken
    function requestRedeem(uint256 shares, address controller, address owner)
        public
        override(ComponentToken)
        nonReentrant
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
        uint256 precisionReductionFactor = 10 ** orderContract.orderDecimalReduction(dshareToken);
        // slither-disable-next-line divide-before-multiply
        uint256 orderAmount = (dshares / precisionReductionFactor) * precisionReductionFactor;

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
        SafeERC20.safeIncreaseAllowance(IERC20(dshareToken), address(orderContract), orderAmount);
        // Sell
        IOrderProcessor.Order memory order = IOrderProcessor.Order({
            requestTimestamp: $.orderNonce++,
            recipient: address(this),
            assetToken: dshareToken,
            paymentToken: asset(),
            sell: true,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: orderAmount,
            paymentTokenQuantity: 0,
            price: 0,
            tif: IOrderProcessor.TIF.DAY
        });
        requestId = orderContract.createOrderStandardFees(order);
        $.submittedOrderInfo[requestId] = DShareOrderInfo({sell: true, orderAmount: orderAmount, fees: 0});
        $.submittedOrders.pushBack(bytes32(requestId));
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

    function processSubmittedOrders() public nonReentrant {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        IOrderProcessor orderContract = $.externalOrderContract;
        address nestStakingContract = $.nestStakingContract;
        IERC20 dshareToken = IERC20($.dshareToken);
        IERC4626 wrappedDshareToken = IERC4626($.wrappedDshareToken);
        IERC20 paymentToken = IERC20(asset());

        DoubleEndedQueue.Bytes32Deque storage orders = $.submittedOrders;
        while (orders.length() > 0) {
            uint256 orderId = uint256(orders.front());

            IOrderProcessor.OrderStatus status = _processOrder(
                orderId, orderContract, nestStakingContract, dshareToken, wrappedDshareToken, paymentToken
            );
            if (status == IOrderProcessor.OrderStatus.ACTIVE) {
                break;
            }

            // slither-disable-next-line unused-return
            orders.popFront();
        }
    }

    function _processOrder(
        uint256 orderId,
        IOrderProcessor orderContract,
        address nestStakingContract,
        IERC20 dshareToken,
        IERC4626 wrappedDshareToken,
        IERC20 paymentToken
    ) private returns (IOrderProcessor.OrderStatus status) {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();

        status = orderContract.getOrderStatus(orderId);
        if (status == IOrderProcessor.OrderStatus.ACTIVE) {
            return status;
        } else if (status == IOrderProcessor.OrderStatus.NONE) {
            revert OrderDoesNotExist();
        }

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
                SafeERC20.safeIncreaseAllowance(dshareToken, address(wrappedDshareToken), proceeds);
                uint256 shares = wrappedDshareToken.deposit(proceeds, address(this));

                super._notifyDeposit(totalInput, shares, nestStakingContract);

                // Send fee refund to controller
                uint256 totalSpent = orderInfo.orderAmount + orderContract.getFeesTaken(orderId);
                uint256 refund = totalInput - totalSpent;
                if (refund > 0) {
                    SafeERC20.safeTransfer(paymentToken, nestStakingContract, refund);
                }
            }
        }
    }

    /// @dev Single order processing if gas limit is reached
    function processNextSubmittedOrder() public nonReentrant {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        IOrderProcessor orderContract = $.externalOrderContract;
        address nestStakingContract = $.nestStakingContract;
        IERC20 dshareToken = IERC20($.dshareToken);
        IERC4626 wrappedDshareToken = IERC4626($.wrappedDshareToken);
        IERC20 paymentToken = IERC20(asset());

        DoubleEndedQueue.Bytes32Deque storage orders = $.submittedOrders;
        if (orders.length() == 0) {
            revert NoOutstandingOrders();
        }
        uint256 orderId = uint256(orders.front());
        IOrderProcessor.OrderStatus status =
            _processOrder(orderId, orderContract, nestStakingContract, dshareToken, wrappedDshareToken, paymentToken);
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
        nonReentrant
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
        nonReentrant
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
        nonReentrant
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
        nonReentrant
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
