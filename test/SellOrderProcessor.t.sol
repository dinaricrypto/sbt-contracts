// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solady-test/utils/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "./utils/SigUtils.sol";
import "../src/issuer/SellOrderProcessor.sol";
import {OrderFees} from "../src/issuer/OrderFees.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract SellOrderProcessorTest is Test {
    event EscrowTaken(bytes32 indexed orderId, address indexed recipient, uint256 amount);
    event EscrowReturned(bytes32 indexed orderId, address indexed recipient, uint256 amount);

    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees orderFees);
    event OrdersPaused(bool paused);

    event OrderRequested(bytes32 indexed id, address indexed recipient, IOrderBridge.Order order, bytes32 salt);
    event OrderFill(bytes32 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount);
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

        token.setMinter(address(this), true);
        token.setMinter(address(issuer), true);

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);

        dummyOrder = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: 100 ether
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

    function testRequestOrder(uint128 quantityIn) public {
        OrderProcessor.OrderRequest memory order = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: quantityIn
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
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(orderId, user, bridgeOrderData, salt);
            vm.prank(user);
            issuer.requestOrder(order, salt);
            assertTrue(issuer.isOrderActive(orderId));
            assertEq(issuer.getRemainingOrder(orderId), quantityIn);
            assertEq(issuer.numOpenOrders(), 1);
            assertEq(issuer.getOrderId(bridgeOrderData, salt), orderId);
            assertEq(token.balanceOf(address(issuer)), quantityIn);
        }
    }

    function testFillOrder(uint128 orderAmount, uint128 fillAmount, uint256 receivedAmount) public {
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
            }
        }
    }

    function testCancelOrder(uint128 orderAmount, uint128 fillAmount, string calldata reason) public {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount > 0);
        vm.assume(fillAmount < orderAmount);

        OrderProcessor.OrderRequest memory order = dummyOrder;
        order.quantityIn = orderAmount;

        token.mint(user, orderAmount);
        vm.prank(user);
        token.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        paymentToken.mint(operator, 100);
        vm.prank(operator);
        paymentToken.increaseAllowance(address(issuer), 100);

        vm.prank(operator);
        issuer.fillOrder(order, salt, fillAmount, 100);

        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);
        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(orderId, user, reason);
        vm.prank(operator);
        issuer.cancelOrder(order, salt, reason);
    }
}
