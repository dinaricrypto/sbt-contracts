// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "../src/issuer/LimitBuyOrder.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";

contract LimitBuyOrderTest is Test {
    event OrderFill(bytes32 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount);
    event OrderRequested(bytes32 indexed id, address indexed recipient, IOrderBridge.Order order, bytes32 salt);

    BridgedERC20 token;
    OrderFees orderFees;
    LimitBuyOrder issuer;
    MockERC20 paymentToken;

    uint256 userPrivateKey;
    address user;

    address constant operator = address(3);
    address constant treasury = address(4);

    bytes32 constant salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
    OrderProcessor.OrderRequest dummyOrder;
    uint256 dummyOrderFees;
    IOrderBridge.Order dummyOrderBridgeData;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockBridgedERC20();
        paymentToken = new MockERC20("Money", "$", 6);

        orderFees = new OrderFees(address(this), 1 ether, 0.005 ether);

        LimitBuyOrder issuerImpl = new LimitBuyOrder();
        issuer = LimitBuyOrder(
            address(
                new ERC1967Proxy(address(issuerImpl), abi.encodeCall(issuerImpl.initialize, (address(this), treasury, orderFees)))
            )
        );

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
    }

    function testRequestOrderLimit(uint256 quantityIn, uint256 _price) public {
        dummyOrder = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: quantityIn,
            price: _price
        });
        bytes32 orderId = issuer.getOrderIdFromOrderRequest(dummyOrder, salt);

        (uint256 flatFee, uint256 percentageFee) =
            issuer.getFeesForOrder(dummyOrder.paymentToken, dummyOrder.quantityIn);
        uint256 fees = flatFee + percentageFee;
        IOrderBridge.Order memory bridgeOrderData = IOrderBridge.Order({
            recipient: dummyOrder.recipient,
            assetToken: dummyOrder.assetToken,
            paymentToken: dummyOrder.paymentToken,
            sell: false,
            orderType: IOrderBridge.OrderType.LIMIT,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 0,
            price: 0,
            tif: IOrderBridge.TIF.GTC,
            fee: fees
        });
        bridgeOrderData.paymentTokenQuantity = 0;
        if (quantityIn > fees) {
            bridgeOrderData.paymentTokenQuantity = quantityIn - fees;
        }

        paymentToken.mint(user, dummyOrder.quantityIn);
        vm.startPrank(user);
        paymentToken.increaseAllowance(address(issuer), dummyOrder.quantityIn);

        if (quantityIn == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(user);
            issuer.requestOrder(dummyOrder, salt);
        } else if (fees >= quantityIn) {
            vm.expectRevert(BuyOrderIssuer.OrderTooSmall.selector);
            vm.prank(user);
            issuer.requestOrder(dummyOrder, salt);
        } else {
            uint256 userBalanceBefore = paymentToken.balanceOf(user);
            uint256 issuerBalanceBefore = paymentToken.balanceOf(address(issuer));
            if (_price == 0) {
                vm.expectRevert(LimitBuyOrder.LimitPriceNotSet.selector);
                issuer.requestOrder(dummyOrder, salt);
            } else {
                bridgeOrderData.price = dummyOrder.price;
                vm.expectEmit(true, true, true, true);
                emit OrderRequested(orderId, user, bridgeOrderData, salt);
                vm.prank(user);
                issuer.requestOrder(dummyOrder, salt);
                assertTrue(issuer.isOrderActive(orderId));
                assertEq(issuer.getRemainingOrder(orderId), quantityIn - fees);
                assertEq(issuer.numOpenOrders(), 1);
                assertEq(issuer.getOrderId(bridgeOrderData, salt), orderId);
                // balances after
                assertEq(paymentToken.balanceOf(address(user)), userBalanceBefore - quantityIn);
                assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + quantityIn);
            }
        }
    }

    function testFillOrderLimit(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount, uint256 _price) public {
        vm.assume(_price > 0 && _price < 1e3);
        OrderProcessor.OrderRequest memory order = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: orderAmount,
            price: _price
        });

        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.paymentToken, order.quantityIn);
        uint256 fees = flatFee + percentageFee;
        vm.assume(fees < orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
        } else {
            uint256 userAssetBefore = token.balanceOf(user);
            uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
            uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);


            // vm.assume(fillAmount > receivedAmount * order.price);
            // vm.expectRevert(LimitBuyOrder.OrderFillBelowLimitPrice.selector);
            // vm.prank(operator);
            // issuer.fillOrder(order, salt, fillAmount, receivedAmount);

            // vm.assume(fillAmount < receivedAmount * order.price);
            // vm.prank(operator);
            // issuer.fillOrder(order, salt, fillAmount, receivedAmount);

            // assertEq(issuer.getRemainingOrder(orderId), orderAmount - fees - fillAmount);
            // if (fillAmount == orderAmount - fees) {
            //     assertEq(issuer.numOpenOrders(), 0);
            //     assertEq(issuer.getTotalReceived(orderId), 0);
            // } else {
            //     assertEq(issuer.getTotalReceived(orderId), receivedAmount);
            //     // balances after
            //     assertEq(token.balanceOf(address(user)), userAssetBefore + receivedAmount);
            //     assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore - fillAmount);
            //     assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore + fillAmount);
            // }
        }
    }
}
