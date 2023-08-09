// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";
import {OrderProcessor} from "../src/issuer/OrderProcessor.sol";
import "./utils/mocks/MockdShare.sol";
import "../src/issuer/LimitBuyIssuer.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import {TokenLockCheck, ITokenLockCheck} from "../src/TokenLockCheck.sol";
import {NumberUtils} from "./utils/NumberUtils.sol";

contract LimitBuyIssuerTest is Test {
    event OrderRequested(address indexed recipient, uint256 indexed index, IOrderBridge.Order order);
    event OrderFill(address indexed recipient, uint256 indexed index, uint256 fillAmount, uint256 receivedAmount);

    dShare token;
    OrderFees orderFees;
    TokenLockCheck tokenLockCheck;
    LimitBuyIssuer issuer;
    MockToken paymentToken;

    uint256 userPrivateKey;
    address user;

    address constant operator = address(3);
    address constant treasury = address(4);

    uint256 flatFee;
    uint24 percentageFeeRate;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockdShare();
        paymentToken = new MockToken();

        orderFees = new OrderFees(address(this), 1 ether, 5_000);

        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(paymentToken));

        issuer = new LimitBuyIssuer(address(this), treasury, orderFees, tokenLockCheck);

        (flatFee, percentageFeeRate) = issuer.getFeeRatesForOrder(address(paymentToken));

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
    }

    function createOrder(uint256 orderAmount, uint256 price, uint256 fees)
        internal
        view
        returns (IOrderBridge.Order memory order)
    {
        order = IOrderBridge.Order({
            recipient: user,
            index: 0,
            quantityIn: orderAmount + fees,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderBridge.OrderType.LIMIT,
            assetTokenQuantity: 0,
            paymentTokenQuantity: orderAmount,
            price: price,
            tif: IOrderBridge.TIF.GTC
        });
    }

    function testRequestOrderLimit(uint256 orderAmount, uint256 _price) public {
        uint256 fees = issuer.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        IOrderBridge.Order memory order = createOrder(orderAmount, _price, fees);

        paymentToken.mint(user, order.quantityIn);
        vm.startPrank(user);
        paymentToken.increaseAllowance(address(issuer), order.quantityIn);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);
        if (orderAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            issuer.requestOrder(order);
        } else if (_price == 0) {
            vm.expectRevert(LimitBuyIssuer.LimitPriceNotSet.selector);
            issuer.requestOrder(order);
        } else {
            uint256 userBalanceBefore = paymentToken.balanceOf(user);
            uint256 issuerBalanceBefore = paymentToken.balanceOf(address(issuer));
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(user, order.index, order);
            uint256 index = issuer.requestOrder(order);
            assertEq(index, order.index);
            assertTrue(issuer.isOrderActive(id));
            assertEq(issuer.getRemainingOrder(id), orderAmount);
            assertEq(issuer.numOpenOrders(), 1);
            // balances after
            assertEq(paymentToken.balanceOf(address(user)), userBalanceBefore - order.quantityIn);
            assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + order.quantityIn);
        }
        vm.stopPrank();
    }

    function testFillBuyOrderLimit(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount, uint256 _price)
        public
    {
        vm.assume(_price > 0);
        vm.assume(orderAmount > 0);
        vm.assume(!NumberUtils.mulDivCheckOverflow(fillAmount, 1 ether, _price));
        uint256 fees = issuer.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));

        IOrderBridge.Order memory order = createOrder(orderAmount, _price, fees);

        uint256 feesEarned = 0;
        if (fillAmount > 0) {
            feesEarned = flatFee + PrbMath.mulDiv(fees - flatFee, fillAmount, order.paymentTokenQuantity);
        }

        paymentToken.mint(user, order.quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), order.quantityIn);

        vm.prank(user);
        issuer.requestOrder(order);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);
        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        } else if (receivedAmount < PrbMath.mulDiv(fillAmount, 1 ether, order.price)) {
            vm.expectRevert(LimitBuyIssuer.OrderFillBelowLimitPrice.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        } else {
            // balances before
            uint256 userAssetBefore = token.balanceOf(user);
            uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
            uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
            vm.assume(fillAmount < orderAmount);
            vm.expectEmit(true, true, true, true);
            emit OrderFill(user, order.index, fillAmount, receivedAmount);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
            assertEq(issuer.getRemainingOrder(id), orderAmount - fillAmount);
            if (fillAmount == orderAmount) {
                assertEq(issuer.numOpenOrders(), 0);
                assertEq(issuer.getTotalReceived(id), 0);
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
}
