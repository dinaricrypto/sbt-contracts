// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";
import "./utils/mocks/MockdShare.sol";
import "./utils/SigUtils.sol";
import "../src/issuer/SellOrderProcessor.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import {TokenLockCheck, ITokenLockCheck} from "../src/TokenLockCheck.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import {FeeLib} from "../src/FeeLib.sol";

contract SellOrderProcessorTest is Test {
    event OrderRequested(address indexed recipient, uint256 indexed index, IOrderBridge.Order order);
    event OrderFill(address indexed recipient, uint256 indexed index, uint256 fillAmount, uint256 receivedAmount);
    event OrderFulfilled(address indexed recipient, uint256 indexed index);
    event CancelRequested(address indexed recipient, uint256 indexed index);
    event OrderCancelled(address indexed recipient, uint256 indexed index, string reason);

    dShare token;
    OrderFees orderFees;
    TokenLockCheck tokenLockCheck;
    SellOrderProcessor issuer;
    MockToken paymentToken;

    uint256 userPrivateKey;
    address user;

    address constant operator = address(3);
    address constant treasury = address(4);
    uint256 flatFee;
    uint24 percentageFeeRate;

    IOrderBridge.Order dummyOrder;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockdShare();
        paymentToken = new MockToken();

        orderFees = new OrderFees(address(this), 1 ether, 5_000);

        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(paymentToken));

        issuer = new SellOrderProcessor(address(this), treasury, orderFees, tokenLockCheck);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.BURNER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);

        (flatFee, percentageFeeRate) = issuer.getFeeRatesForOrder(address(paymentToken));
        dummyOrder = IOrderBridge.Order({
            recipient: user,
            index: 0,
            quantityIn: 100 ether,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: true,
            orderType: IOrderBridge.OrderType.MARKET,
            assetTokenQuantity: 100 ether,
            paymentTokenQuantity: 0,
            price: 0,
            tif: IOrderBridge.TIF.GTC
        });
    }

    function testRequestOrder(uint256 quantityIn) public {
        IOrderBridge.Order memory order = dummyOrder;
        order.quantityIn = quantityIn;
        order.assetTokenQuantity = quantityIn;

        token.mint(user, quantityIn);
        vm.prank(user);
        token.increaseAllowance(address(issuer), quantityIn);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);

        if (quantityIn == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(user);
            issuer.requestOrder(order);
        } else {
            // balances before
            uint256 userBalanceBefore = token.balanceOf(user);
            uint256 issuerBalanceBefore = token.balanceOf(address(issuer));
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(order.recipient, order.index, order);
            vm.prank(user);
            issuer.requestOrder(order);
            assertTrue(issuer.isOrderActive(id));
            assertEq(issuer.getRemainingOrder(id), quantityIn);
            assertEq(issuer.numOpenOrders(), 1);
            assertEq(token.balanceOf(address(issuer)), quantityIn);
            // balances after
            assertEq(token.balanceOf(user), userBalanceBefore - quantityIn);
            assertEq(token.balanceOf(address(issuer)), issuerBalanceBefore + quantityIn);
            assertEq(issuer.escrowedBalanceOf(order.assetToken, user), quantityIn);
        }
    }

    function testFillOrder(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount) public {
        vm.assume(orderAmount > 0);

        IOrderBridge.Order memory order = dummyOrder;
        order.quantityIn = orderAmount;
        order.assetTokenQuantity = orderAmount;

        uint256 feesEarned = 0;
        if (receivedAmount > 0) {
            if (receivedAmount <= flatFee) {
                feesEarned = receivedAmount;
            } else {
                feesEarned = flatFee + PrbMath.mulDiv18(receivedAmount - flatFee, percentageFeeRate);
            }
        }

        token.mint(user, orderAmount);
        vm.prank(user);
        token.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order);

        uint256 escrowAmount = issuer.escrowedBalanceOf(order.assetToken, user);
        assertEq(escrowAmount, orderAmount);

        paymentToken.mint(operator, receivedAmount);
        vm.prank(operator);
        paymentToken.increaseAllowance(address(issuer), receivedAmount);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        } else {
            // balances before
            uint256 userPaymentBefore = paymentToken.balanceOf(user);
            uint256 issuerAssetBefore = token.balanceOf(address(issuer));
            uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
            vm.expectEmit(true, true, true, true);
            emit OrderFill(order.recipient, order.index, fillAmount, receivedAmount);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
            assertEq(issuer.getRemainingOrder(id), orderAmount - fillAmount);
            // balances after
            assertEq(paymentToken.balanceOf(user), userPaymentBefore + receivedAmount - feesEarned);
            assertEq(token.balanceOf(address(issuer)), issuerAssetBefore - fillAmount);
            assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore - receivedAmount);
            assertEq(paymentToken.balanceOf(treasury), feesEarned);
            if (fillAmount == orderAmount) {
                assertEq(issuer.numOpenOrders(), 0);
                assertEq(issuer.getTotalReceived(id), 0);
            } else {
                assertEq(issuer.getTotalReceived(id), receivedAmount);
            }
        }
    }

    function testFulfillOrder(
        uint256 orderAmount,
        uint256 firstFillAmount,
        uint256 firstReceivedAmount,
        uint256 receivedAmount
    ) public {
        vm.assume(orderAmount > 0);
        vm.assume(firstFillAmount > 0);
        vm.assume(firstFillAmount <= orderAmount);
        vm.assume(firstReceivedAmount <= receivedAmount);

        IOrderBridge.Order memory order = dummyOrder;
        order.quantityIn = orderAmount;
        order.assetTokenQuantity = orderAmount;

        token.mint(user, orderAmount);
        vm.prank(user);
        token.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order);

        paymentToken.mint(operator, receivedAmount);
        vm.prank(operator);
        paymentToken.increaseAllowance(address(issuer), receivedAmount);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);
        uint256 feesEarned = 0;
        if (receivedAmount > 0) {
            if (receivedAmount <= flatFee) {
                feesEarned = receivedAmount;
            } else {
                feesEarned = flatFee + PrbMath.mulDiv18(receivedAmount - flatFee, percentageFeeRate);
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
            emit OrderFill(order.recipient, order.index, firstFillAmount, firstReceivedAmount);
            vm.prank(operator);
            issuer.fillOrder(order, firstFillAmount, firstReceivedAmount);
            assertEq(issuer.getRemainingOrder(id), orderAmount - firstFillAmount);
            assertEq(issuer.numOpenOrders(), 1);
            assertEq(issuer.getTotalReceived(id), firstReceivedAmount);

            // second fill
            vm.expectEmit(true, true, true, true);
            emit OrderFulfilled(order.recipient, order.index);
            vm.prank(operator);
            issuer.fillOrder(order, secondFillAmount, secondReceivedAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderFulfilled(order.recipient, order.index);
            vm.prank(operator);
            issuer.fillOrder(order, orderAmount, receivedAmount);
        }
        // order closed
        assertEq(issuer.getRemainingOrder(id), 0);
        assertEq(issuer.numOpenOrders(), 0);
        assertEq(issuer.getTotalReceived(id), 0);
        // balances after
        // Fees may be k - 1 (k == number of fills) off due to rounding
        assertApproxEqAbs(paymentToken.balanceOf(user), userPaymentBefore + receivedAmount - feesEarned, 1);
        assertEq(paymentToken.balanceOf(address(issuer)), 0);
        assertEq(token.balanceOf(address(issuer)), 0);
        assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore - receivedAmount);
        assertApproxEqAbs(paymentToken.balanceOf(treasury), feesEarned, 1);
    }

    function testCancelOrder(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount, string calldata reason)
        public
    {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount < orderAmount);

        IOrderBridge.Order memory order = dummyOrder;
        order.quantityIn = orderAmount;
        order.assetTokenQuantity = orderAmount;

        token.mint(user, orderAmount);
        vm.prank(user);
        token.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order);

        uint256 feesEarned = 0;
        if (fillAmount > 0) {
            if (receivedAmount > 0) {
                if (receivedAmount <= flatFee) {
                    feesEarned = receivedAmount;
                } else {
                    feesEarned = flatFee + PrbMath.mulDiv18(receivedAmount - flatFee, percentageFeeRate);
                }
            }

            paymentToken.mint(operator, receivedAmount);
            vm.prank(operator);
            paymentToken.increaseAllowance(address(issuer), receivedAmount);

            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        }

        // balances before
        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(order.recipient, order.index, reason);
        vm.prank(operator);
        issuer.cancelOrder(order, reason);
        // balances after
        assertEq(paymentToken.balanceOf(address(issuer)), 0);
        assertEq(token.balanceOf(address(issuer)), 0);
        if (fillAmount > 0) {
            uint256 escrow = orderAmount - fillAmount;
            assertEq(paymentToken.balanceOf(user), receivedAmount - feesEarned);
            assertEq(token.balanceOf(user), escrow);
            assertEq(paymentToken.balanceOf(treasury), feesEarned);
        } else {
            assertEq(token.balanceOf(user), orderAmount);
        }
    }
}
