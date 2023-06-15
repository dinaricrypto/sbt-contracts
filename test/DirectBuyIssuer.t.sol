// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solady-test/utils/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "../src/issuer/DirectBuyIssuer.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";

contract DirectBuyIssuerTest is Test {
    event EscrowTaken(bytes32 indexed orderId, address indexed recipient, uint256 amount);
    event EscrowReturned(bytes32 indexed orderId, address indexed recipient, uint256 amount);

    event OrderRequested(bytes32 indexed id, address indexed recipient, IOrderBridge.Order order, bytes32 salt);
    event OrderFill(bytes32 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount);
    event CancelRequested(bytes32 indexed id, address indexed recipient);
    event OrderCancelled(bytes32 indexed id, address indexed recipient, string reason);

    BridgedERC20 token;
    OrderFees orderFees;
    DirectBuyIssuer issuer;
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

        DirectBuyIssuer issuerImpl = new DirectBuyIssuer();
        issuer = DirectBuyIssuer(
            address(
                new ERC1967Proxy(address(issuerImpl), abi.encodeCall(issuerImpl.initialize, (address(this), treasury, orderFees)))
            )
        );

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);

        dummyOrder = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: 100 ether
        });
        (uint256 flatFee, uint256 percentageFee) =
            issuer.getFeesForOrder(dummyOrder.paymentToken, dummyOrder.quantityIn);
        dummyOrderFees = flatFee + percentageFee;
        dummyOrderBridgeData = IOrderBridge.Order({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderBridge.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: dummyOrder.quantityIn - dummyOrderFees,
            price: 0,
            tif: IOrderBridge.TIF.GTC,
            fee: dummyOrderFees
        });
    }

    function testTakeEscrow(uint256 orderAmount, uint256 takeAmount) public {
        vm.assume(orderAmount > 0);

        OrderProcessor.OrderRequest memory order = dummyOrder;
        order.quantityIn = orderAmount;
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.paymentToken, order.quantityIn);
        uint256 fees = flatFee + percentageFee;
        vm.assume(fees < orderAmount);

        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);
        if (takeAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.takeEscrow(order, salt, takeAmount);
        } else if (takeAmount > orderAmount - fees) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.takeEscrow(order, salt, takeAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit EscrowTaken(orderId, user, takeAmount);
            vm.prank(operator);
            issuer.takeEscrow(order, salt, takeAmount);
            assertEq(paymentToken.balanceOf(operator), takeAmount);
            assertEq(issuer.getOrderEscrow(orderId), orderAmount - fees - takeAmount);
        }
    }

    function testReturnEscrow(uint256 orderAmount, uint256 returnAmount) public {
        vm.assume(orderAmount > 0);

        OrderProcessor.OrderRequest memory order = dummyOrder;
        order.quantityIn = orderAmount;
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.paymentToken, order.quantityIn);
        uint256 fees = flatFee + percentageFee;
        vm.assume(fees < orderAmount);

        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        uint256 takeAmount = orderAmount - fees;
        vm.prank(operator);
        issuer.takeEscrow(order, salt, takeAmount);

        vm.prank(operator);
        paymentToken.increaseAllowance(address(issuer), returnAmount);

        if (returnAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.returnEscrow(order, salt, returnAmount);
        } else if (returnAmount > takeAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.returnEscrow(order, salt, returnAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit EscrowReturned(orderId, user, returnAmount);
            vm.prank(operator);
            issuer.returnEscrow(order, salt, returnAmount);
            assertEq(issuer.getOrderEscrow(orderId), returnAmount);
            assertEq(paymentToken.balanceOf(address(issuer)), fees + returnAmount);
        }
    }

    function testFillOrder(uint256 orderAmount, uint256 takeAmount, uint256 fillAmount, uint256 receivedAmount)
        public
    {
        vm.assume(takeAmount > 0);

        OrderProcessor.OrderRequest memory order = dummyOrder;
        order.quantityIn = orderAmount;
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.paymentToken, order.quantityIn);
        uint256 fees = flatFee + percentageFee;
        vm.assume(fees <= orderAmount);
        vm.assume(takeAmount <= orderAmount - fees);

        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        vm.prank(operator);
        issuer.takeEscrow(order, salt, takeAmount);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount - fees || fillAmount > takeAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderFill(orderId, user, fillAmount, receivedAmount);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
            assertEq(issuer.getRemainingOrder(orderId), orderAmount - fees - fillAmount);
            if (fillAmount == orderAmount) {
                assertEq(issuer.numOpenOrders(), 0);
                assertEq(issuer.getTotalReceived(orderId), 0);
            } else {
                assertEq(issuer.getTotalReceived(orderId), receivedAmount);
            }
        }
    }

    function testCancelOrder(uint256 orderAmount, uint256 fillAmount, string calldata reason) public {
        vm.assume(orderAmount > 0);

        OrderProcessor.OrderRequest memory order = dummyOrder;
        order.quantityIn = orderAmount;
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.assetToken, order.quantityIn);
        uint256 fees = flatFee + percentageFee;
        vm.assume(fees < orderAmount);
        vm.assume(fillAmount < orderAmount - fees);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        if (fillAmount > 0) {
            vm.prank(operator);
            issuer.takeEscrow(order, salt, fillAmount);

            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, 100);
        }

        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);
        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(orderId, user, reason);
        vm.prank(operator);
        issuer.cancelOrder(order, salt, reason);
    }

    function testCancelOrderUnreturnedEscrowReverts(uint256 orderAmount, uint256 takeAmount) public {
        vm.assume(orderAmount > 0);
        vm.assume(takeAmount > 0);

        OrderProcessor.OrderRequest memory order = dummyOrder;
        order.quantityIn = orderAmount;
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.assetToken, order.quantityIn);
        uint256 fees = flatFee + percentageFee;
        vm.assume(fees < orderAmount);
        vm.assume(takeAmount < orderAmount - fees);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        vm.prank(operator);
        issuer.takeEscrow(order, salt, takeAmount);

        vm.expectRevert(DirectBuyIssuer.UnreturnedEscrow.selector);
        vm.prank(operator);
        issuer.cancelOrder(order, salt, "");
    }
}
