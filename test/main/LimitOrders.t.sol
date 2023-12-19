// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {MockToken} from "../utils/mocks/MockToken.sol";
import {OrderProcessor} from "../../src/orders/OrderProcessor.sol";
import "../utils/mocks/MockDShareFactory.sol";
import "../../src/orders/OrderProcessor.sol";
import "../../src/orders/IOrderProcessor.sol";
import {TokenLockCheck, ITokenLockCheck} from "../../src/TokenLockCheck.sol";
import {NumberUtils} from "../../src/common/NumberUtils.sol";
import {FeeLib} from "../../src/common/FeeLib.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract LimitOrderTest is Test {
    event OrderRequested(uint256 indexed id, address indexed recipient, IOrderProcessor.Order order);
    event OrderFill(
        uint256 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount, uint256 feesPaid
    );

    MockDShareFactory tokenFactory;
    DShare token;
    TokenLockCheck tokenLockCheck;
    OrderProcessor issuer;
    MockToken paymentToken;

    uint256 userPrivateKey;
    uint256 adminPrivateKey;
    address user;
    address admin;

    address constant operator = address(3);
    address constant treasury = address(4);

    uint256 flatFee;
    uint24 percentageFeeRate;

    function setUp() public {
        userPrivateKey = 0x01;
        adminPrivateKey = 0x02;
        user = vm.addr(userPrivateKey);
        admin = vm.addr(adminPrivateKey);

        vm.startPrank(admin);
        tokenFactory = new MockDShareFactory();
        token = tokenFactory.deploy("Dinari Token", "dTKN");
        paymentToken = new MockToken("Money", "$");

        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(paymentToken));

        OrderProcessor issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl),
                    abi.encodeCall(
                        OrderProcessor.initialize,
                        (
                            admin,
                            treasury,
                            OrderProcessor.FeeRates({
                                perOrderFeeBuy: 1 ether,
                                percentageFeeRateBuy: 5_000,
                                perOrderFeeSell: 1 ether,
                                percentageFeeRateSell: 5_000
                            }),
                            tokenLockCheck
                        )
                    )
                )
            )
        );

        (flatFee, percentageFeeRate) = issuer.getFeeRatesForOrder(user, false, address(paymentToken));

        token.grantRole(token.MINTER_ROLE(), admin);
        token.grantRole(token.MINTER_ROLE(), address(issuer));
        token.grantRole(token.BURNER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
        issuer.setMaxOrderDecimals(address(token), int8(token.decimals()));

        vm.stopPrank();
    }

    function createLimitOrder(bool sell, uint256 orderAmount, uint256 price)
        internal
        view
        returns (IOrderProcessor.Order memory order)
    {
        order = IOrderProcessor.Order({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: sell,
            orderType: IOrderProcessor.OrderType.LIMIT,
            assetTokenQuantity: sell ? orderAmount : 0,
            paymentTokenQuantity: sell ? 0 : orderAmount,
            price: price,
            tif: IOrderProcessor.TIF.GTC,
            splitAmount: 0,
            splitRecipient: address(0)
        });
    }

    function testRequestBuyOrderLimit(uint256 orderAmount, uint256 _price) public {
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        IOrderProcessor.Order memory order = createLimitOrder(false, orderAmount, _price);

        vm.startPrank(admin);
        paymentToken.mint(user, order.paymentTokenQuantity + fees);
        vm.startPrank(user);
        paymentToken.approve(address(issuer), order.paymentTokenQuantity + fees);

        if (orderAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            issuer.requestOrder(order);
        } else if (_price == 0) {
            vm.expectRevert(OrderProcessor.LimitPriceNotSet.selector);
            issuer.requestOrder(order);
        } else {
            uint256 userBalanceBefore = paymentToken.balanceOf(user);
            uint256 issuerBalanceBefore = paymentToken.balanceOf(address(issuer));
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(0, user, order);
            uint256 id = issuer.requestOrder(order);
            assertEq(id, 0);
            assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
            assertEq(issuer.getUnfilledAmount(id), order.paymentTokenQuantity);
            assertEq(issuer.numOpenOrders(), 1);
            // balances after
            assertEq(paymentToken.balanceOf(address(user)), userBalanceBefore - (order.paymentTokenQuantity + fees));
            assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + (order.paymentTokenQuantity + fees));
        }
        vm.stopPrank();
    }

    function testFillBuyOrderLimit(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount, uint256 _price)
        public
    {
        vm.assume(_price > 0);
        vm.assume(orderAmount > 0);
        vm.assume(!NumberUtils.mulDivCheckOverflow(fillAmount, 1 ether, _price));
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));

        IOrderProcessor.Order memory order = createLimitOrder(false, orderAmount, _price);

        uint256 feesEarned = 0;
        if (fillAmount > 0) {
            feesEarned = flatFee + mulDiv(fees - flatFee, fillAmount, order.paymentTokenQuantity);
        }

        vm.prank(admin);
        paymentToken.mint(user, order.paymentTokenQuantity + fees);
        vm.prank(user);
        paymentToken.approve(address(issuer), order.paymentTokenQuantity + fees);

        vm.prank(user);
        uint256 id = issuer.requestOrder(order);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(id, order, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(id, order, fillAmount, receivedAmount);
        } else if (receivedAmount < mulDiv(fillAmount, 1 ether, order.price)) {
            vm.expectRevert(OrderProcessor.OrderFillBelowLimitPrice.selector);
            vm.prank(operator);
            issuer.fillOrder(id, order, fillAmount, receivedAmount);
        } else {
            // balances before
            uint256 userAssetBefore = token.balanceOf(user);
            uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
            uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
            vm.assume(fillAmount < orderAmount);
            vm.expectEmit(true, true, true, false);
            // since we can't capture the function var without rewritting the _fillOrderAccounting inside the test
            emit OrderFill(id, order.recipient, fillAmount, receivedAmount, 0);
            vm.prank(operator);
            issuer.fillOrder(id, order, fillAmount, receivedAmount);
            assertEq(issuer.getUnfilledAmount(id), orderAmount - fillAmount);
            if (fillAmount == orderAmount) {
                assertEq(issuer.numOpenOrders(), 0);
                assertEq(issuer.getTotalReceived(id), 0);
                assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.FULFILLED));
            } else {
                assertEq(issuer.getTotalReceived(id), receivedAmount);
                // balances after
                assertEq(token.balanceOf(address(user)), userAssetBefore + receivedAmount);
                assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore - fillAmount - feesEarned);
                assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore + fillAmount);
                assertEq(paymentToken.balanceOf(treasury), feesEarned);
            }
        }
    }

    function testRequestOrderLimit(uint256 orderAmount, uint256 _price) public {
        IOrderProcessor.Order memory order = createLimitOrder(true, orderAmount, _price);

        vm.prank(admin);
        token.mint(user, orderAmount);
        vm.prank(user);
        token.approve(address(issuer), orderAmount);

        if (orderAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(user);
            issuer.requestOrder(order);
        } else if (_price == 0) {
            vm.expectRevert(OrderProcessor.LimitPriceNotSet.selector);
            vm.prank(user);
            issuer.requestOrder(order);
        } else {
            // balances before
            uint256 userBalanceBefore = token.balanceOf(user);
            uint256 issuerBalanceBefore = token.balanceOf(address(issuer));
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(0, user, order);
            vm.prank(user);
            uint256 id = issuer.requestOrder(order);
            assertEq(id, 0);
            assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
            assertEq(issuer.getUnfilledAmount(id), orderAmount);
            assertEq(issuer.numOpenOrders(), 1);
            assertEq(token.balanceOf(address(issuer)), orderAmount);
            // balances after
            assertEq(token.balanceOf(user), userBalanceBefore - orderAmount);
            assertEq(token.balanceOf(address(issuer)), issuerBalanceBefore + orderAmount);
        }
    }

    function testFillSellOrderLimit(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount, uint256 _price)
        public
    {
        vm.assume(orderAmount > 0);
        vm.assume(_price > 0 && _price < 2 ** 128 - 1);
        vm.assume(fillAmount < 2 ** 128 - 1);
        vm.assume(receivedAmount < 2 ** 128 - 1);

        IOrderProcessor.Order memory order = createLimitOrder(true, orderAmount, _price);

        vm.prank(admin);
        token.mint(user, orderAmount);
        vm.prank(user);
        token.approve(address(issuer), orderAmount);

        vm.prank(user);
        uint256 id = issuer.requestOrder(order);

        vm.prank(admin);
        paymentToken.mint(operator, receivedAmount); // Mint paymentTokens to operator to ensure they have enough
        vm.prank(operator);
        paymentToken.approve(address(issuer), receivedAmount);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(id, order, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(id, order, fillAmount, receivedAmount);
        } else if (receivedAmount < mulDiv18(fillAmount, order.price)) {
            vm.expectRevert(OrderProcessor.OrderFillAboveLimitPrice.selector);
            vm.prank(operator);
            issuer.fillOrder(id, order, fillAmount, receivedAmount);
        } else {
            // balances before
            uint256 issuerAssetBefore = token.balanceOf(address(issuer));
            uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
            vm.expectEmit(true, true, true, false);
            // since we can't capture the function var without rewritting the _fillOrderAccounting inside the test
            emit OrderFill(id, order.recipient, fillAmount, receivedAmount, 0);
            vm.prank(operator);
            issuer.fillOrder(id, order, fillAmount, receivedAmount);
            assertEq(issuer.getUnfilledAmount(id), orderAmount - fillAmount);
            if (fillAmount == orderAmount) {
                assertEq(issuer.numOpenOrders(), 0);
                assertEq(issuer.getTotalReceived(id), 0);
                assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.FULFILLED));
            } else {
                assertEq(issuer.getTotalReceived(id), receivedAmount);
                assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
                // balances after
                // assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore + receivedAmount);
                assertEq(token.balanceOf(address(issuer)), issuerAssetBefore - fillAmount);
                assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore - receivedAmount);
            }
        }
    }
}
