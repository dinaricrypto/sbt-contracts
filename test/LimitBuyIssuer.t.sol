// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OrderProcessor} from "../src/issuer/OrderProcessor.sol";
import "./utils/mocks/MockdShare.sol";
import "../src/issuer/LimitBuyIssuer.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import {TokenLockCheck, ITokenLockCheck} from "../src/TokenLockCheck.sol";

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
    uint64 percentageFeeRate;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockdShare();
        paymentToken = new MockToken();

        orderFees = new OrderFees(address(this), 1 ether, 0.005 ether);

        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(paymentToken));
        issuer = new LimitBuyIssuer(address(this), treasury, orderFees, tokenLockCheck);
        (flatFee, percentageFeeRate) = issuer.getFeeRatesForOrder(address(paymentToken));

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
    }

    function createOrderAndRequest(uint256 quantityIn, uint256 price, uint256 fees)
        internal
        view
        returns (IOrderBridge.OrderRequest memory orderRequest, IOrderBridge.Order memory order)
    {
        orderRequest = IOrderBridge.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: quantityIn,
            price: price
        });
        order = IOrderBridge.Order({
            recipient: orderRequest.recipient,
            index: 0,
            quantityIn: quantityIn,
            assetToken: orderRequest.assetToken,
            paymentToken: orderRequest.paymentToken,
            sell: false,
            orderType: IOrderBridge.OrderType.LIMIT,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 0,
            price: price,
            tif: IOrderBridge.TIF.GTC
        });
        order.paymentTokenQuantity = 0;
        if (quantityIn > fees) {
            order.paymentTokenQuantity = quantityIn - fees;
        }
    }

    function testRequestOrderLimit(uint256 quantityIn, uint256 _price) public {
        uint256 fees = issuer.estimateTotalFees(flatFee, percentageFeeRate, quantityIn);
        (IOrderBridge.OrderRequest memory orderRequest, IOrderBridge.Order memory order) =
            createOrderAndRequest(quantityIn, _price, fees);

        paymentToken.mint(user, orderRequest.quantityIn);
        vm.startPrank(user);
        paymentToken.increaseAllowance(address(issuer), orderRequest.quantityIn);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);
        if (quantityIn == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            issuer.requestOrder(orderRequest);
        } else if (fees >= quantityIn) {
            vm.expectRevert(BuyOrderIssuer.OrderTooSmall.selector);
            issuer.requestOrder(orderRequest);
        } else if (_price == 0) {
            vm.expectRevert(LimitBuyIssuer.LimitPriceNotSet.selector);
            issuer.requestOrder(orderRequest);
        } else {
            uint256 userBalanceBefore = paymentToken.balanceOf(user);
            uint256 issuerBalanceBefore = paymentToken.balanceOf(address(issuer));
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(user, order.index, order);
            uint256 index = issuer.requestOrder(orderRequest);
            assertEq(index, order.index);
            assertTrue(issuer.isOrderActive(id));
            assertEq(issuer.getRemainingOrder(id), quantityIn - fees);
            assertEq(issuer.numOpenOrders(), 1);
            // balances after
            assertEq(paymentToken.balanceOf(address(user)), userBalanceBefore - quantityIn);
            assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + quantityIn);
        }
        vm.stopPrank();
    }

    function testFillBuyOrderLimit(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount, uint256 _price)
        public
    {
        vm.assume(_price > 0 && _price < 2 ** 128 - 1);
        vm.assume(fillAmount < 2 ** 128 - 1);
        vm.assume(receivedAmount < 2 ** 128 - 1);
        vm.assume(orderAmount > 0);

        uint256 fees = 0;
        {
            fees = issuer.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
            vm.assume(fees < orderAmount);
        }
        (IOrderBridge.OrderRequest memory orderRequest, IOrderBridge.Order memory order) =
            createOrderAndRequest(orderAmount, _price, fees);

        uint256 feesEarned = 0;
        if (fillAmount > 0) {
            feesEarned = flatFee + PrbMath.mulDiv(fees - flatFee, fillAmount, order.paymentTokenQuantity);
        }

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(orderRequest);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);
        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount - fees) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        } else if (fillAmount > PrbMath.mulDiv18(receivedAmount, order.price)) {
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
            assertEq(issuer.getRemainingOrder(id), orderAmount - fees - fillAmount);
            if (fillAmount == orderAmount - fees) {
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
