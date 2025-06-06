// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";
import "./utils/mocks/GetMockDShareFactory.sol";
import "./utils/SigUtils.sol";
import "../src/orders/OrderProcessor.sol";
import "../src/orders/IOrderProcessor.sol";
import "../src/orders/LatestPriceHelper.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {NumberUtils} from "../src/common/NumberUtils.sol";
import {FeeLib} from "../src/common/FeeLib.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract OrderProcessorTest is Test {
    using GetMockDShareFactory for DShareFactory;

    event TreasurySet(address indexed treasury);
    event VaultSet(address indexed vault);
    event PaymentTokenSet(
        address indexed paymentToken,
        bytes4 blacklistCallSelector,
        uint64 perOrderFeeBuy,
        uint24 percentageFeeRateBuy,
        uint64 perOrderFeeSell,
        uint24 percentageFeeRateSell
    );
    event PaymentTokenRemoved(address indexed paymentToken);
    event OrdersPaused(bool paused);
    event OrderDecimalReductionSet(address indexed assetToken, uint8 decimalReduction);
    event OperatorSet(address indexed account, bool set);

    event OrderCreated(
        uint256 indexed id, address indexed requester, IOrderProcessor.Order order, uint256 feesEscrowed
    );
    event OrderFill(
        uint256 indexed id,
        address indexed paymentToken,
        address indexed assetToken,
        address requester,
        uint256 assetAmount,
        uint256 paymentAmount,
        uint256 fees,
        bool sell
    );
    event OrderFulfilled(uint256 indexed id, address indexed recipient);
    event CancelRequested(uint256 indexed id, address indexed requester);
    event OrderCancelled(uint256 indexed id, address indexed recipient, string reason);

    struct FeeRates {
        uint64 perOrderFeeBuy;
        uint24 percentageFeeRateBuy;
        uint64 perOrderFeeSell;
        uint24 percentageFeeRateSell;
    }

    DShareFactory tokenFactory;
    DShare token;
    OrderProcessor issuer;
    MockToken paymentToken;
    SigUtils sigUtils;
    TransferRestrictor restrictor;
    LatestPriceHelper latestPriceHelper;

    uint256 userPrivateKey;
    uint256 adminPrivateKey;
    address user;
    address admin;

    address constant operator = address(3);
    address constant treasury = address(4);
    address constant upgrader = address(5);
    address public restrictor_role = address(1);

    uint256 dummyOrderFees;

    function setUp() public {
        userPrivateKey = 0x01;
        adminPrivateKey = 0x02;
        user = vm.addr(userPrivateKey);
        admin = vm.addr(adminPrivateKey);

        vm.startPrank(admin);
        (tokenFactory,,) = GetMockDShareFactory.getMockDShareFactory(admin);
        token = tokenFactory.deployDShare(admin, "Dinari Token", "dTKN");
        paymentToken = new MockToken("Money", "$");
        sigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());

        OrderProcessor issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl),
                    abi.encodeCall(OrderProcessor.initialize, (admin, upgrader, treasury, operator, tokenFactory))
                )
            )
        );

        token.grantRole(token.MINTER_ROLE(), admin);
        token.grantRole(token.MINTER_ROLE(), address(issuer));
        token.grantRole(token.BURNER_ROLE(), address(issuer));

        issuer.setPaymentToken(address(paymentToken), paymentToken.isBlacklisted.selector, 1e8, 5_000, 1e8, 5_000);
        issuer.setOperator(operator, true);

        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(paymentToken));
        dummyOrderFees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, 100 ether);

        restrictor = TransferRestrictor(address(token.transferRestrictor()));
        restrictor.grantRole(restrictor.RESTRICTOR_ROLE(), restrictor_role);

        latestPriceHelper = new LatestPriceHelper();
        vm.stopPrank();
    }

    function getDummyOrder(bool sell) internal view returns (IOrderProcessor.Order memory) {
        return IOrderProcessor.Order({
            requestTimestamp: uint64(block.timestamp),
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: sell,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: sell ? 100 ether : 0,
            paymentTokenQuantity: sell ? 0 : 100 ether,
            price: 0,
            tif: IOrderProcessor.TIF.GTC
        });
    }

    function testInitialization() public {
        assertEq(issuer.owner(), admin);
        assertEq(issuer.treasury(), treasury);
        assertEq(issuer.vault(), operator);
        assertEq(address(issuer.dShareFactory()), address(tokenFactory));
    }

    function testInitializationReverts() public {
        OrderProcessor issuerImpl = new OrderProcessor();

        vm.expectRevert(OrderProcessor.ZeroAddress.selector);
        new ERC1967Proxy(
            address(issuerImpl),
            abi.encodeCall(OrderProcessor.initialize, (admin, upgrader, address(0), operator, tokenFactory))
        );

        vm.expectRevert(OrderProcessor.ZeroAddress.selector);
        new ERC1967Proxy(
            address(issuerImpl),
            abi.encodeCall(OrderProcessor.initialize, (admin, upgrader, treasury, address(0), tokenFactory))
        );

        vm.expectRevert(OrderProcessor.ZeroAddress.selector);
        new ERC1967Proxy(
            address(issuerImpl),
            abi.encodeCall(OrderProcessor.initialize, (admin, upgrader, treasury, operator, DShareFactory(address(0))))
        );
    }

    function testUpgrade() public {
        OrderProcessor issuerImpl = new OrderProcessor();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), issuer.UPGRADER_ROLE()
            )
        );
        issuer.upgradeToAndCall(address(issuerImpl), "");

        vm.prank(upgrader);
        issuer.upgradeToAndCall(address(issuerImpl), "");
    }

    function testSetTreasury(address account) public {
        vm.assume(account != address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), issuer.DEFAULT_ADMIN_ROLE()
            )
        );
        issuer.setTreasury(account);

        vm.expectEmit(true, true, true, true);
        emit TreasurySet(account);
        vm.prank(admin);
        issuer.setTreasury(account);
        assertEq(issuer.treasury(), account);
    }

    function testSetTreasuryZeroReverts() public {
        vm.expectRevert(OrderProcessor.ZeroAddress.selector);
        vm.prank(admin);
        issuer.setTreasury(address(0));
    }

    function testSetVault(address account) public {
        vm.assume(account != address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), issuer.DEFAULT_ADMIN_ROLE()
            )
        );
        issuer.setVault(account);

        vm.expectEmit(true, true, true, true);
        emit VaultSet(account);
        vm.prank(admin);
        issuer.setVault(account);
        assertEq(issuer.vault(), account);
    }

    function testSetVaultZeroReverts() public {
        vm.expectRevert(OrderProcessor.ZeroAddress.selector);
        vm.prank(admin);
        issuer.setVault(address(0));
    }

    function testFlatFeeForOrder(uint8 tokenDecimals, uint64 perOrderFee) public {
        MockERC20 newToken = new MockERC20("Test Token", "TEST", tokenDecimals);
        if (tokenDecimals > 18) {
            vm.expectRevert(FeeLib.DecimalsTooLarge.selector);
            this.wrapFlatFeeForOrder(tokenDecimals, perOrderFee);
        } else {
            assertEq(
                wrapFlatFeeForOrder(tokenDecimals, perOrderFee), decimalAdjust(8, newToken.decimals(), perOrderFee)
            );
        }
    }

    function testSetPaymentToken(address oracle, uint64 perOrderFee, uint24 percentageFeeRate) public {
        vm.assume(percentageFeeRate < 1_000_000);
        vm.assume(oracle != address(0));

        MockToken testToken = new MockToken("Test Token", "TEST");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), issuer.DEFAULT_ADMIN_ROLE()
            )
        );
        issuer.setPaymentToken(
            address(testToken),
            testToken.isBlacklisted.selector,
            perOrderFee,
            percentageFeeRate,
            perOrderFee,
            percentageFeeRate
        );

        vm.expectRevert(Address.FailedInnerCall.selector);
        vm.prank(admin);
        issuer.setPaymentToken(
            address(testToken),
            0x032f29a1, // lock selector doesn't exist for token contract
            perOrderFee,
            percentageFeeRate,
            perOrderFee,
            percentageFeeRate
        );

        vm.expectEmit(true, true, true, true);
        emit PaymentTokenSet(
            address(testToken),
            testToken.isBlacklisted.selector,
            perOrderFee,
            percentageFeeRate,
            perOrderFee,
            percentageFeeRate
        );
        vm.prank(admin);
        issuer.setPaymentToken(
            address(testToken),
            testToken.isBlacklisted.selector,
            perOrderFee,
            percentageFeeRate,
            perOrderFee,
            percentageFeeRate
        );
        OrderProcessor.PaymentTokenConfig memory config = issuer.getPaymentTokenConfig(address(testToken));
        assertTrue(config.enabled);
        assertEq(config.decimals, testToken.decimals());
        assertEq(config.blacklistCallSelector, testToken.isBlacklisted.selector);
        assertEq(config.perOrderFeeBuy, perOrderFee);
        assertEq(config.percentageFeeRateBuy, percentageFeeRate);
        assertEq(config.perOrderFeeSell, perOrderFee);
        assertEq(config.percentageFeeRateSell, percentageFeeRate);

        testToken.blacklist(user);
        assertTrue(issuer.isTransferLocked(address(testToken), user));
    }

    function testRemovePaymentToken(address testToken) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), issuer.DEFAULT_ADMIN_ROLE()
            )
        );
        issuer.removePaymentToken(testToken);

        vm.expectEmit(true, true, true, true);
        emit PaymentTokenRemoved(testToken);
        vm.prank(admin);
        issuer.removePaymentToken(testToken);

        vm.expectRevert(abi.encodeWithSelector(OrderProcessor.UnsupportedToken.selector, testToken));
        issuer.getStandardFees(false, testToken);
    }

    function testSetOrdersPaused(bool pause) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), issuer.DEFAULT_ADMIN_ROLE()
            )
        );
        issuer.setOrdersPaused(pause);

        vm.expectEmit(true, true, true, true);
        emit OrdersPaused(pause);
        vm.prank(admin);
        issuer.setOrdersPaused(pause);
        assertEq(issuer.ordersPaused(), pause);
    }

    function testSetOperator(address account, bool set) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), issuer.DEFAULT_ADMIN_ROLE()
            )
        );
        issuer.setOperator(account, set);

        vm.expectEmit(true, true, true, true);
        emit OperatorSet(account, set);
        vm.prank(admin);
        issuer.setOperator(account, set);
        assertEq(issuer.isOperator(account), set);
    }

    function testRequestOrderZeroAmountReverts(bool sell) public {
        IOrderProcessor.Order memory order = getDummyOrder(sell);
        order.paymentTokenQuantity = 0;
        order.assetTokenQuantity = 0;

        vm.expectRevert(OrderProcessor.ZeroValue.selector);
        vm.prank(user);
        issuer.createOrderStandardFees(order);
    }

    function testRequestBuyOrder(address recipient, uint256 orderAmount) public {
        vm.assume(recipient != address(0));
        vm.assume(orderAmount > 0);

        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(paymentToken));
        uint256 fees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));

        IOrderProcessor.Order memory order = getDummyOrder(false);
        order.recipient = recipient;
        order.paymentTokenQuantity = orderAmount;
        uint256 quantityIn = order.paymentTokenQuantity + fees;

        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        uint256 orderId = issuer.hashOrder(order);

        // balances before
        uint256 userBalanceBefore = paymentToken.balanceOf(user);
        uint256 operatorBalanceBefore = paymentToken.balanceOf(operator);
        vm.expectEmit(true, true, true, true);
        emit OrderCreated(orderId, user, order, fees);
        vm.prank(user);
        uint256 id = issuer.createOrderStandardFees(order);
        uint256 receivedAmount = issuer.getReceivedAmount(id);
        assertEq(id, orderId);
        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(id), order.paymentTokenQuantity);
        assertEq(receivedAmount, 0);
        assertEq(issuer.getFeesEscrowed(id), fees);
        assertEq(paymentToken.balanceOf(user), userBalanceBefore - quantityIn);
        assertEq(paymentToken.balanceOf(operator), operatorBalanceBefore + orderAmount);
        assertEq(paymentToken.balanceOf(address(issuer)), fees);
    }

    function testRequestBuyOrderBlacklistUnspecified(uint256 orderAmount) public {
        vm.assume(orderAmount > 0);

        vm.prank(admin);
        MockERC20 newToken = new MockERC20("Test Token", "TEST", 6);

        vm.prank(admin);
        issuer.setPaymentToken(address(newToken), bytes4(0), 1e8, 5_000, 1e8, 5_000);

        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(newToken));
        uint256 fees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));

        IOrderProcessor.Order memory order = getDummyOrder(false);
        order.paymentToken = address(newToken);
        order.paymentTokenQuantity = orderAmount;
        uint256 quantityIn = order.paymentTokenQuantity + fees;

        vm.prank(admin);
        newToken.mint(user, quantityIn);
        vm.prank(user);
        newToken.approve(address(issuer), quantityIn);

        uint256 orderId = issuer.hashOrder(order);

        // balances before
        vm.expectEmit(true, true, true, true);
        emit OrderCreated(orderId, user, order, fees);
        vm.prank(user);
        uint256 id = issuer.createOrderStandardFees(order);
        assertEq(id, orderId);
    }

    function testRequestSellOrder(uint256 orderAmount) public {
        vm.assume(orderAmount > 0);

        IOrderProcessor.Order memory order = getDummyOrder(true);
        order.assetTokenQuantity = orderAmount;

        vm.prank(admin);
        token.mint(user, orderAmount);
        vm.prank(user);
        token.approve(address(issuer), orderAmount);

        // balances before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 id = issuer.hashOrder(order);
        vm.expectEmit(true, true, true, true);
        emit OrderCreated(id, user, order, 0);
        vm.prank(user);
        uint256 id2 = issuer.createOrderStandardFees(order);
        assertEq(id, id2);
        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(id), orderAmount);
        assertEq(token.balanceOf(user), userBalanceBefore - orderAmount);
    }

    function testRequestOrderZeroAddressReverts(bool sell) public {
        IOrderProcessor.Order memory order = getDummyOrder(sell);
        order.recipient = address(0);

        vm.expectRevert(OrderProcessor.ZeroAddress.selector);
        vm.prank(user);
        issuer.createOrderStandardFees(order);
    }

    function testRequestOrderPausedReverts(bool sell) public {
        vm.prank(admin);
        issuer.setOrdersPaused(true);

        vm.expectRevert(OrderProcessor.Paused.selector);
        vm.prank(user);
        issuer.createOrderStandardFees(getDummyOrder(sell));
    }

    function testAssetTokenBlacklistReverts(bool sell) public {
        // restrict msg.sender
        vm.prank(restrictor_role);
        restrictor.restrict(user);

        vm.expectRevert(OrderProcessor.Blacklist.selector);
        vm.prank(user);
        issuer.createOrderStandardFees(getDummyOrder(sell));
    }

    function testPaymentTokenBlackListReverts(bool sell) public {
        vm.prank(admin);
        paymentToken.blacklist(user);
        assert(issuer.isTransferLocked(address(paymentToken), user));

        vm.expectRevert(OrderProcessor.Blacklist.selector);
        vm.prank(user);
        issuer.createOrderStandardFees(getDummyOrder(sell));
    }

    function testRequestOrderUnsupportedPaymentReverts(bool sell) public {
        address tryPaymentToken = address(new MockToken("Money", "$"));

        IOrderProcessor.Order memory order = getDummyOrder(sell);
        order.paymentToken = tryPaymentToken;

        vm.expectRevert(abi.encodeWithSelector(OrderProcessor.UnsupportedToken.selector, tryPaymentToken));
        vm.prank(user);
        issuer.createOrderStandardFees(order);
    }

    function testRequestOrderUnsupportedAssetReverts(bool sell) public {
        address tryAssetToken = address(new MockToken("Asset", "X"));

        IOrderProcessor.Order memory order = getDummyOrder(sell);
        order.assetToken = tryAssetToken;

        vm.expectRevert(abi.encodeWithSelector(OrderProcessor.UnsupportedToken.selector, tryAssetToken));
        vm.prank(user);
        issuer.createOrderStandardFees(order);
    }

    function testRequestSellOrderInvalidPrecision() public {
        uint256 orderAmount = 100000255;
        OrderProcessor.Order memory order = getDummyOrder(true);
        uint8 tokenDecimals = token.decimals();

        vm.expectEmit(true, true, true, true);
        emit OrderDecimalReductionSet(order.assetToken, tokenDecimals);
        vm.prank(admin);
        issuer.setOrderDecimalReduction(order.assetToken, tokenDecimals);
        assertEq(issuer.orderDecimalReduction(order.assetToken), tokenDecimals);
        order.assetTokenQuantity = orderAmount;

        vm.prank(admin);
        token.mint(user, order.assetTokenQuantity);
        vm.prank(user);
        token.approve(address(issuer), order.assetTokenQuantity);

        vm.expectRevert(OrderProcessor.InvalidPrecision.selector);
        vm.prank(user);
        issuer.createOrderStandardFees(order);

        // update OrderAmount
        order.assetTokenQuantity = 10 ** tokenDecimals;

        vm.prank(admin);
        token.mint(user, order.assetTokenQuantity);
        vm.prank(user);
        token.approve(address(issuer), order.assetTokenQuantity);

        vm.prank(user);
        issuer.createOrderStandardFees(order);
    }

    function testRequestBuyOrderWithPermit() public {
        IOrderProcessor.Order memory dummyOrder = getDummyOrder(false);
        uint256 quantityIn = dummyOrder.paymentTokenQuantity + dummyOrderFees;
        vm.prank(admin);
        paymentToken.mint(user, quantityIn * 1e6);

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: user,
            spender: address(issuer),
            value: quantityIn,
            nonce: 0,
            deadline: block.timestamp + 30 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            issuer.selfPermit.selector, address(paymentToken), permit.owner, permit.value, permit.deadline, v, r, s
        );
        calls[1] = abi.encodeWithSelector(OrderProcessor.createOrderStandardFees.selector, dummyOrder);

        uint256 orderId = issuer.hashOrder(dummyOrder);

        // balances before
        uint256 userBalanceBefore = paymentToken.balanceOf(user);
        uint256 operatorBalanceBefore = paymentToken.balanceOf(operator);
        vm.expectEmit(true, true, true, true);
        emit OrderCreated(orderId, user, dummyOrder, dummyOrderFees);
        vm.prank(user);
        issuer.multicall(calls);
        assertEq(paymentToken.nonces(user), 1);
        assertEq(paymentToken.allowance(user, address(issuer)), 0);
        assertEq(uint8(issuer.getOrderStatus(orderId)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(orderId), dummyOrder.paymentTokenQuantity);
        assertEq(paymentToken.balanceOf(user), userBalanceBefore - quantityIn);
        assertEq(paymentToken.balanceOf(operator), operatorBalanceBefore + dummyOrder.paymentTokenQuantity);
    }

    function testFillBuyOrder(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount, uint256 fees) public {
        vm.assume(orderAmount > 0);
        uint256 flatFee;
        uint256 feesMax;
        {
            uint24 percentageFeeRate;
            (flatFee, percentageFeeRate) = issuer.getStandardFees(false, address(paymentToken));
            feesMax = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, orderAmount);
            vm.assume(!NumberUtils.addCheckOverflow(orderAmount, feesMax));
        }
        uint256 quantityIn = orderAmount + feesMax;

        IOrderProcessor.Order memory order = getDummyOrder(false);
        order.paymentTokenQuantity = orderAmount;

        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        vm.prank(user);
        uint256 id = issuer.createOrderStandardFees(order);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount, fees);
        } else if (fillAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount, fees);
        } else if (fees > feesMax) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount, fees);
        } else {
            // balances before
            uint256 userAssetBefore = token.balanceOf(user);
            vm.expectEmit(true, true, true, true);
            // since we can't capture
            emit OrderFill(
                id, order.paymentToken, order.assetToken, order.recipient, receivedAmount, fillAmount, fees, false
            );
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount, fees);
            assertEq(issuer.getUnfilledAmount(id), orderAmount - fillAmount);
            IOrderProcessor.PricePoint memory fillPrice = issuer.latestFillPrice(order.assetToken, order.paymentToken);
            if (fillPrice.price > 0) {
                assertEq(
                    fillPrice.price,
                    mulDiv(fillAmount, 10 ** (token.decimals() + 18 - paymentToken.decimals()), receivedAmount)
                );
            }
            address[] memory paymentTokens = new address[](1);
            paymentTokens[0] = order.paymentToken;
            IOrderProcessor.PricePoint memory fillPrice2 =
                latestPriceHelper.aggregateLatestPriceFromProcessor(address(issuer), order.assetToken, paymentTokens);
            assertEq(fillPrice2.price, fillPrice.price);
            assertEq(fillPrice2.blocktime, fillPrice.blocktime);
            // balances after
            assertEq(token.balanceOf(address(user)), userAssetBefore + receivedAmount);
            assertEq(paymentToken.balanceOf(treasury), fees);
            if (fillAmount == orderAmount) {
                // if order is fullfilled in on time
                assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.FULFILLED));
                assertEq(paymentToken.balanceOf(user), feesMax - fees);
                assertEq(issuer.getReceivedAmount(id), receivedAmount);
            } else {
                assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
                assertEq(paymentToken.balanceOf(address(issuer)), feesMax - fees);
                assertEq(issuer.getFeesTaken(id), fees);
            }
        }
    }

    function testFillSellOrder(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount, uint256 fees) public {
        vm.assume(orderAmount > 0);

        IOrderProcessor.Order memory order = getDummyOrder(true);
        order.assetTokenQuantity = orderAmount;

        vm.prank(admin);
        token.mint(user, orderAmount);
        vm.prank(user);
        token.approve(address(issuer), orderAmount);

        vm.prank(user);
        uint256 id = issuer.createOrderStandardFees(order);

        vm.prank(admin);
        paymentToken.mint(operator, receivedAmount);
        vm.prank(operator);
        paymentToken.approve(address(issuer), receivedAmount);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount, fees);
        } else if (fillAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount, fees);
        } else if (fees > receivedAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount, fees);
        } else {
            // balances before
            uint256 userPaymentBefore = paymentToken.balanceOf(user);
            uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
            vm.expectEmit(true, true, true, false);
            // since we can't capture the function var without rewritting the _fillOrderAccounting inside the test
            emit OrderFill(
                id, order.paymentToken, order.assetToken, order.recipient, fillAmount, receivedAmount, 0, true
            );
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount, fees);
            assertEq(issuer.getUnfilledAmount(id), orderAmount - fillAmount);
            // balances after
            assertEq(paymentToken.balanceOf(user), userPaymentBefore + receivedAmount - fees);
            assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore - receivedAmount);
            assertEq(paymentToken.balanceOf(treasury), fees);
            if (fillAmount == orderAmount) {
                assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.FULFILLED));
            } else {
                assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
            }
            assertEq(issuer.getReceivedAmount(id), receivedAmount);
        }
    }

    function testFulfillBuyOrder(uint256 orderAmount, uint256 receivedAmount) public {
        vm.assume(orderAmount > 0);
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(paymentToken));
        uint256 fees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderProcessor.Order memory order = getDummyOrder(false);
        order.paymentTokenQuantity = orderAmount;

        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        vm.prank(user);
        uint256 id = issuer.createOrderStandardFees(order);

        // balances before
        uint256 userAssetBefore = token.balanceOf(user);
        uint256 treasuryPaymentBefore = paymentToken.balanceOf(treasury);
        vm.expectEmit(true, true, true, true);
        emit OrderFulfilled(id, order.recipient);
        vm.prank(operator);
        issuer.fillOrder(order, orderAmount, receivedAmount, fees);
        assertEq(issuer.getUnfilledAmount(id), 0);
        // balances after
        assertEq(token.balanceOf(address(user)), userAssetBefore + receivedAmount);
        assertEq(paymentToken.balanceOf(treasury), treasuryPaymentBefore + fees);
        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.FULFILLED));
    }

    function testFulfillSellOrder(
        uint256 orderAmount,
        uint256 firstFillAmount,
        uint256 firstReceivedAmount,
        uint256 receivedAmount
    ) public {
        vm.assume(orderAmount > 0);
        vm.assume(firstFillAmount > 0);
        vm.assume(firstFillAmount <= orderAmount);
        vm.assume(firstReceivedAmount <= receivedAmount);

        IOrderProcessor.Order memory order = getDummyOrder(true);
        order.assetTokenQuantity = orderAmount;

        vm.prank(admin);
        token.mint(user, orderAmount);
        vm.prank(user);
        token.approve(address(issuer), orderAmount);

        vm.prank(user);
        uint256 id = issuer.createOrderStandardFees(order);

        vm.prank(admin);
        paymentToken.mint(operator, receivedAmount);
        vm.prank(operator);
        paymentToken.approve(address(issuer), receivedAmount);

        uint256 feesEarned = 0;
        if (receivedAmount > 0) {
            (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(true, address(paymentToken));
            if (receivedAmount <= flatFee) {
                feesEarned = receivedAmount;
            } else {
                feesEarned = flatFee + mulDiv18(receivedAmount - flatFee, percentageFeeRate);
            }
        }

        // balances before
        uint256 userPaymentBefore = paymentToken.balanceOf(user);
        uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
        if (firstFillAmount < orderAmount) {
            uint256 secondFillAmount = orderAmount - firstFillAmount;
            uint256 secondReceivedAmount = receivedAmount - firstReceivedAmount;
            // first fill
            vm.expectEmit(true, true, true, true);
            emit OrderFill(
                id, order.paymentToken, order.assetToken, order.recipient, firstFillAmount, firstReceivedAmount, 0, true
            );
            vm.prank(operator);
            issuer.fillOrder(order, firstFillAmount, firstReceivedAmount, 0);
            assertEq(issuer.getUnfilledAmount(id), orderAmount - firstFillAmount);

            // second fill
            feesEarned = feesEarned > secondReceivedAmount ? secondReceivedAmount : feesEarned;
            vm.expectEmit(true, true, true, true);
            emit OrderFulfilled(id, order.recipient);
            vm.prank(operator);
            issuer.fillOrder(order, secondFillAmount, secondReceivedAmount, feesEarned);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderFulfilled(id, order.recipient);
            vm.prank(operator);
            issuer.fillOrder(order, orderAmount, receivedAmount, feesEarned);
        }
        // order closed
        assertEq(issuer.getUnfilledAmount(id), 0);
        // balances after
        // Fees may be k - 1 (k == number of fills) off due to rounding
        assertApproxEqAbs(paymentToken.balanceOf(user), userPaymentBefore + receivedAmount - feesEarned, 1);
        assertEq(paymentToken.balanceOf(address(issuer)), 0);
        assertEq(token.balanceOf(address(issuer)), 0);
        assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore - receivedAmount);
        assertApproxEqAbs(paymentToken.balanceOf(treasury), feesEarned, 1);
        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.FULFILLED));
    }

    function testFillOrderNoOrderReverts(bool sell) public {
        vm.expectRevert(OrderProcessor.OrderNotActive.selector);
        vm.prank(operator);
        issuer.fillOrder(getDummyOrder(sell), 100, 100, 10);
    }

    function testRequestCancel() public {
        IOrderProcessor.Order memory dummyOrder = getDummyOrder(false);
        uint256 quantityIn = dummyOrder.paymentTokenQuantity + dummyOrderFees;

        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        vm.prank(user);
        uint256 id = issuer.createOrderStandardFees(dummyOrder);

        vm.expectEmit(true, true, true, true);
        emit CancelRequested(id, user);
        vm.prank(user);
        issuer.requestCancel(id);
    }

    function testRequestCancelNotRequesterReverts() public {
        IOrderProcessor.Order memory dummyOrder = getDummyOrder(false);
        uint256 quantityIn = dummyOrder.paymentTokenQuantity + dummyOrderFees;
        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        vm.prank(user);
        uint256 id = issuer.createOrderStandardFees(dummyOrder);

        vm.expectRevert(OrderProcessor.NotRequester.selector);
        issuer.requestCancel(id);

        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
    }

    function testRequestCancelNotFoundReverts(uint256 id) public {
        vm.expectRevert(OrderProcessor.OrderNotActive.selector);
        vm.prank(user);
        issuer.requestCancel(id);
    }

    function testCancelOrder(uint256 orderAmount, uint256 fillAmount, string calldata reason) public {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount < orderAmount);
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(paymentToken));
        uint256 fees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderProcessor.Order memory order = getDummyOrder(false);
        order.paymentTokenQuantity = orderAmount;

        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        vm.prank(user);
        uint256 id = issuer.createOrderStandardFees(order);

        uint256 feesEarned = 0;
        if (fillAmount > 0) {
            feesEarned = flatFee + mulDiv(fees - flatFee, fillAmount, order.paymentTokenQuantity);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, 100, feesEarned);
        }

        uint256 unfilledAmount = orderAmount - fillAmount;

        vm.prank(operator);
        paymentToken.approve(address(issuer), unfilledAmount);

        // balances before
        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(id, order.recipient, reason);
        vm.prank(operator);
        issuer.cancelOrder(order, reason);
        assertEq(paymentToken.balanceOf(address(issuer)), 0);
        assertEq(paymentToken.balanceOf(treasury), feesEarned);
        // balances after
        if (fillAmount > 0) {
            assertEq(paymentToken.balanceOf(address(user)), quantityIn - fillAmount - feesEarned);
        } else {
            assertEq(paymentToken.balanceOf(address(user)), quantityIn);
        }
        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.CANCELLED));
    }

    function testCancelSellOrder(uint256 orderAmount, uint256 fillAmount, string calldata reason) public {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount < orderAmount);

        IOrderProcessor.Order memory order = getDummyOrder(true);
        order.assetTokenQuantity = orderAmount;

        vm.prank(admin);
        token.mint(user, orderAmount);
        vm.prank(user);
        token.approve(address(issuer), orderAmount);

        vm.prank(user);
        uint256 id = issuer.createOrderStandardFees(order);

        // balances before
        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(id, order.recipient, reason);
        vm.prank(operator);
        issuer.cancelOrder(order, reason);
        assertEq(token.balanceOf(address(issuer)), 0);
        // balances after
        assertEq(token.balanceOf(address(user)), orderAmount);
        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.CANCELLED));
    }

    function testCancelOrderNotActiveReverts() public {
        vm.expectRevert(OrderProcessor.OrderNotActive.selector);
        vm.prank(operator);
        issuer.cancelOrder(getDummyOrder(false), "msg");
    }

    // ------------------ utils ------------------

    function wrapFlatFeeForOrder(uint8 newTokenDecimals, uint64 perOrderFee) public pure returns (uint256) {
        return FeeLib.flatFeeForOrder(newTokenDecimals, perOrderFee);
    }

    function decimalAdjust(uint8 startDecimals, uint8 decimals, uint256 fee) internal pure returns (uint256) {
        uint256 adjFee = fee;
        if (decimals < startDecimals) {
            adjFee /= 10 ** (startDecimals - decimals);
        } else if (decimals > startDecimals) {
            adjFee *= 10 ** (decimals - startDecimals);
        }
        return adjFee;
    }
}
