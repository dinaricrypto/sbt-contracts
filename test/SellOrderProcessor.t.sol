// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "./utils/SigUtils.sol";
import "../src/issuer/SellOrderProcessor.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract SellOrderProcessorTest is Test {
    event OrderRequested(bytes32 indexed id, address indexed recipient, IOrderBridge.Order order, bytes32 salt);
    event OrderFill(bytes32 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount);
    event OrderFulfilled(bytes32 indexed id, address indexed recipient);
    event CancelRequested(bytes32 indexed id, address indexed recipient);
    event OrderCancelled(bytes32 indexed id, address indexed recipient, string reason);

    BridgedERC20 token;
    OrderFees orderFees;
    SellOrderProcessor issuer;
    MockERC20 paymentToken;

    uint256 userPrivateKey;
    address user;

    address constant operator = address(3);
    address constant treasury = address(4);

    bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
    OrderProcessor.OrderRequest dummyOrder;
    IOrderBridge.Order dummyOrderBridgeData;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockBridgedERC20();
        paymentToken = new MockERC20("Money", "$", 6);

        orderFees = new OrderFees(address(this), 1 ether, 0.005 ether);

        SellOrderProcessor issuerImpl = new SellOrderProcessor();
        issuer = SellOrderProcessor(
            address(
                new ERC1967Proxy(address(issuerImpl), abi.encodeCall(issuerImpl.initialize, (address(this), treasury, orderFees)))
            )
        );

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.BURNER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);

        dummyOrder = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: 100 ether,
            price: 0
        });
        dummyOrderBridgeData = IOrderBridge.Order({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: true,
            orderType: IOrderBridge.OrderType.MARKET,
            assetTokenQuantity: dummyOrder.quantityIn,
            paymentTokenQuantity: 0,
            price: 0,
            tif: IOrderBridge.TIF.GTC,
            fee: 0
        });
    }

    function testNoFees(uint256 value) public {
        issuer.setOrderFees(IOrderFees(address(0)));

        uint256 flatFee = issuer.getFlatFeeForOrder(address(paymentToken));
        uint256 percentageFee = issuer.getPercentageFeeForOrder(value);
        assertEq(flatFee, 0);
        assertEq(percentageFee, 0);
    }

    function testRequestOrder(uint256 quantityIn) public {
        OrderProcessor.OrderRequest memory order = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: quantityIn,
            price: 0
        });
        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);

        IOrderBridge.Order memory bridgeOrderData = IOrderBridge.Order({
            recipient: order.recipient,
            assetToken: order.assetToken,
            paymentToken: order.paymentToken,
            sell: true,
            orderType: IOrderBridge.OrderType.MARKET,
            assetTokenQuantity: quantityIn,
            paymentTokenQuantity: 0,
            price: 0,
            tif: IOrderBridge.TIF.GTC,
            fee: 0
        });

        token.mint(user, quantityIn);
        vm.prank(user);
        token.increaseAllowance(address(issuer), quantityIn);

        if (quantityIn == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(user);
            issuer.requestOrder(order, salt);
        } else {
            // balances before
            uint256 userBalanceBefore = token.balanceOf(user);
            uint256 issuerBalanceBefore = token.balanceOf(address(issuer));
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(orderId, user, bridgeOrderData, salt);
            vm.prank(user);
            issuer.requestOrder(order, salt);
            assertTrue(issuer.isOrderActive(orderId));
            assertEq(issuer.getRemainingOrder(orderId), quantityIn);
            assertEq(issuer.numOpenOrders(), 1);
            assertEq(issuer.getOrderId(bridgeOrderData, salt), orderId);
            assertEq(token.balanceOf(address(issuer)), quantityIn);
            // balances after
            assertEq(token.balanceOf(user), userBalanceBefore - quantityIn);
            assertEq(token.balanceOf(address(issuer)), issuerBalanceBefore + quantityIn);
        }
    }

    function testFillOrder(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount) public {
        vm.assume(orderAmount > 0);

        OrderProcessor.OrderRequest memory order = dummyOrder;
        order.quantityIn = orderAmount;

        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);

        token.mint(user, orderAmount);
        vm.prank(user);
        token.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        paymentToken.mint(operator, receivedAmount);
        vm.prank(operator);
        paymentToken.increaseAllowance(address(issuer), receivedAmount);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
        } else {
            // balances before
            uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
            uint256 issuerAssetBefore = token.balanceOf(address(issuer));
            uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
            vm.expectEmit(true, true, true, true);
            emit OrderFill(orderId, user, fillAmount, receivedAmount);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
            assertEq(issuer.getRemainingOrder(orderId), orderAmount - fillAmount);
            if (fillAmount == orderAmount) {
                assertEq(issuer.numOpenOrders(), 0);
                assertEq(issuer.getTotalReceived(orderId), 0);
            } else {
                assertEq(issuer.getTotalReceived(orderId), receivedAmount);
                // balances after
                assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore + receivedAmount);
                assertEq(token.balanceOf(address(issuer)), issuerAssetBefore - fillAmount);
                assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore - receivedAmount);
            }
        }
    }

    function testFulfillOrder(uint256 orderAmount, uint256 receivedAmount) public {
        vm.assume(orderAmount > 0);

        OrderProcessor.OrderRequest memory order = dummyOrder;
        order.quantityIn = orderAmount;

        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);

        token.mint(user, orderAmount);
        vm.prank(user);
        token.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        paymentToken.mint(operator, receivedAmount);
        vm.prank(operator);
        paymentToken.increaseAllowance(address(issuer), receivedAmount);

        // balances before
        uint256 userPaymentBefore = paymentToken.balanceOf(user);
        uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
        uint256 issuerAssetBefore = token.balanceOf(address(issuer));
        uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
        uint256 treasuryPaymentBefore = paymentToken.balanceOf(treasury);
        vm.expectEmit(true, true, true, true);
        emit OrderFulfilled(orderId, user);
        vm.prank(operator);
        issuer.fillOrder(order, salt, orderAmount, receivedAmount);
        assertEq(issuer.getRemainingOrder(orderId), 0);
        assertEq(issuer.numOpenOrders(), 0);
        assertEq(issuer.getTotalReceived(orderId), 0);
        // balances after
        uint256 flatFee = issuer.getFlatFeeForOrder(address(paymentToken));
        uint256 percentageFee = issuer.getPercentageFeeForOrder(receivedAmount);
        uint256 fees = flatFee + percentageFee;
        if (fees > receivedAmount) fees = receivedAmount;
        assertEq(paymentToken.balanceOf(user), userPaymentBefore + receivedAmount - fees);
        assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore);
        assertEq(token.balanceOf(address(issuer)), issuerAssetBefore - orderAmount);
        assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore - receivedAmount);
        assertEq(paymentToken.balanceOf(treasury), treasuryPaymentBefore + fees);
    }

    function testCancelOrder(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount, string calldata reason)
        public
    {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount < orderAmount);

        OrderProcessor.OrderRequest memory order = dummyOrder;
        order.quantityIn = orderAmount;

        token.mint(user, orderAmount);
        vm.prank(user);
        token.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        if (fillAmount > 0) {
            paymentToken.mint(operator, receivedAmount);
            vm.prank(operator);
            paymentToken.increaseAllowance(address(issuer), receivedAmount);

            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
        }

        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);

        // balances before
        uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
        uint256 issuerAssetBefore = token.balanceOf(address(issuer));
        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(orderId, user, reason);
        vm.prank(operator);
        issuer.cancelOrder(order, salt, reason);
        // balances after
        if (fillAmount > 0) {
            uint256 flatFee = issuer.getFlatFeeForOrder(address(paymentToken));
            uint256 percentageFee = issuer.getPercentageFeeForOrder(receivedAmount);
            uint256 fees = percentageFee + flatFee;
            if (fees > receivedAmount) fees = receivedAmount;
            uint256 escrow = orderAmount - fillAmount;
            assertEq(paymentToken.balanceOf(user), receivedAmount - fees);
            assertEq(token.balanceOf(user), escrow);
            assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore - receivedAmount);
            assertEq(token.balanceOf(address(issuer)), issuerAssetBefore - escrow);
            assertEq(paymentToken.balanceOf(treasury), fees);
        } else {
            assertEq(token.balanceOf(user), orderAmount);
            assertEq(token.balanceOf(address(issuer)), issuerAssetBefore - orderAmount);
        }
    }
}
