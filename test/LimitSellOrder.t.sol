// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "../src/issuer/LimitSellOrder.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";

contract LimitSellOrderTest is Test {
    event OrderFill(bytes32 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount);
    event OrderRequested(bytes32 indexed id, address indexed recipient, IOrderBridge.Order order, bytes32 salt);

    BridgedERC20 token;
    OrderFees orderFees;
    LimitSellOrder issuer;
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

        LimitSellOrder issuerImpl = new LimitSellOrder();
        issuer = LimitSellOrder(
            address(
                new ERC1967Proxy(address(issuerImpl), abi.encodeCall(issuerImpl.initialize, (address(this), treasury, orderFees)))
            )
        );

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.BURNER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
    }

    function testRequestOrderLimit(uint256 quantityIn, uint256 _price) public {
        OrderProcessor.OrderRequest memory order = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: quantityIn,
            price: _price
        });
        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);

        IOrderBridge.Order memory bridgeOrderData = IOrderBridge.Order({
            recipient: order.recipient,
            assetToken: order.assetToken,
            paymentToken: order.paymentToken,
            sell: true,
            orderType: IOrderBridge.OrderType.LIMIT,
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
            if (_price == 0) {
                vm.expectRevert(LimitSellOrder.LimitPriceNotSet.selector);
                vm.prank(user);
                issuer.requestOrder(order, salt);
            } else {
                bridgeOrderData.price = order.price;
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
    }

    function testFillSellOrderLimit(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount) public {
        vm.assume(orderAmount > 0);

        OrderProcessor.OrderRequest memory order = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: orderAmount,
            price: 1
        });

        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);

        token.mint(user, orderAmount);
        vm.prank(user);
        token.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        paymentToken.mint(operator, receivedAmount); // Mint paymentTokens to operator to ensure they have enough
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
            uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
            uint256 issuerAssetBefore = token.balanceOf(address(issuer));
            uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);

            vm.assume(receivedAmount < fillAmount * order.price);
            vm.expectRevert(LimitSellOrder.OrderFillAboveLimitPrice.selector);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);

            vm.assume(receivedAmount > fillAmount * order.price);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
            assertEq(issuer.getRemainingOrder(orderId), orderAmount - fillAmount);
            assertEq(issuer.getTotalReceived(orderId), receivedAmount);
            // balances after
            assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore + receivedAmount);
            assertEq(token.balanceOf(address(issuer)), issuerAssetBefore - fillAmount);
            assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore - receivedAmount);
        }
    }
}
