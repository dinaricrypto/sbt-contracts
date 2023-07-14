// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "../src/issuer/DirectBuyIssuer.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";

contract DirectBuyIssuerTest is Test {
    event EscrowTaken(address indexed recipient, uint256 indexed index, uint256 amount);
    event EscrowReturned(address indexed recipient, uint256 indexed index, uint256 amount);

    event OrderRequested(address indexed recipient, uint256 indexed index, IOrderBridge.Order order);
    event OrderFill(address indexed recipient, uint256 indexed index, uint256 fillAmount, uint256 receivedAmount);
    event CancelRequested(address indexed recipient, uint256 indexed index);
    event OrderCancelled(address indexed recipient, uint256 indexed index, string reason);

    BridgedERC20 token;
    OrderFees orderFees;
    DirectBuyIssuer issuer;
    MockERC20 paymentToken;

    uint256 userPrivateKey;
    address user;

    address constant operator = address(3);
    address constant treasury = address(4);

    OrderProcessor.OrderRequest dummyOrderRequest;
    uint256 dummyOrderFees;
    IOrderBridge.Order dummyOrder;

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

        dummyOrderRequest = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: 100 ether,
            price: 0
        });
        (uint256 flatFee, uint256 percentageFee) =
            issuer.getFeesForOrder(dummyOrderRequest.paymentToken, dummyOrderRequest.quantityIn);
        dummyOrderFees = flatFee + percentageFee;
        dummyOrder = IOrderBridge.Order({
            recipient: user,
            index: 0,
            quantityIn: dummyOrderRequest.quantityIn,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderBridge.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: dummyOrderRequest.quantityIn - dummyOrderFees,
            price: 0,
            tif: IOrderBridge.TIF.GTC
        });
    }

    function testTakeEscrow(uint256 orderAmount, uint256 takeAmount) public {
        vm.assume(orderAmount > 0);

        OrderProcessor.OrderRequest memory order = dummyOrderRequest;
        order.quantityIn = orderAmount;

        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.paymentToken, order.quantityIn);
        uint256 fees = flatFee + percentageFee;
        vm.assume(fees < orderAmount);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        bytes32 id = issuer.getOrderId(dummyOrder.recipient, dummyOrder.index);

        vm.prank(user);
        issuer.requestOrder(order);
        if (takeAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.takeEscrow(dummyOrder, takeAmount);
        } else if (takeAmount > orderAmount - fees) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.takeEscrow(dummyOrder, takeAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit EscrowTaken(dummyOrder.recipient, dummyOrder.index, takeAmount);
            vm.prank(operator);
            issuer.takeEscrow(dummyOrder, takeAmount);
            assertEq(paymentToken.balanceOf(operator), takeAmount);
            assertEq(issuer.getOrderEscrow(id), orderAmount - fees - takeAmount);
        }
    }

    function testReturnEscrow(uint256 orderAmount, uint256 returnAmount) public {
        vm.assume(orderAmount > 0);

        OrderProcessor.OrderRequest memory order = dummyOrderRequest;
        order.quantityIn = orderAmount;
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.paymentToken, order.quantityIn);
        uint256 fees = flatFee + percentageFee;
        vm.assume(fees < orderAmount);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order);

        uint256 takeAmount = orderAmount - fees;
        vm.prank(operator);
        issuer.takeEscrow(dummyOrder, takeAmount);

        vm.prank(operator);
        paymentToken.increaseAllowance(address(issuer), returnAmount);

        bytes32 id = issuer.getOrderId(dummyOrder.recipient, dummyOrder.index);

        if (returnAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.returnEscrow(dummyOrder, returnAmount);
        } else if (returnAmount > takeAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.returnEscrow(dummyOrder, returnAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit EscrowReturned(dummyOrder.recipient, dummyOrder.index, returnAmount);
            vm.prank(operator);
            issuer.returnEscrow(dummyOrder, returnAmount);
            assertEq(issuer.getOrderEscrow(id), returnAmount);
            assertEq(paymentToken.balanceOf(address(issuer)), fees + returnAmount);
        }
    }

    function testFillOrder(uint256 orderAmount, uint256 takeAmount, uint256 fillAmount, uint256 receivedAmount)
        public
    {
        vm.assume(takeAmount > 0);

        OrderProcessor.OrderRequest memory order = dummyOrderRequest;
        order.quantityIn = orderAmount;
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.paymentToken, order.quantityIn);
        uint256 fees = flatFee + percentageFee;
        vm.assume(fees <= orderAmount);
        vm.assume(takeAmount <= orderAmount - fees);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order);

        vm.prank(operator);
        issuer.takeEscrow(dummyOrder, takeAmount);

        bytes32 id = issuer.getOrderId(dummyOrder.recipient, dummyOrder.index);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(dummyOrder, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount - fees || fillAmount > takeAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(dummyOrder, fillAmount, receivedAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderFill(dummyOrder.recipient, dummyOrder.index, fillAmount, receivedAmount);
            vm.prank(operator);
            issuer.fillOrder(dummyOrder, fillAmount, receivedAmount);
            assertEq(issuer.getRemainingOrder(id), orderAmount - fees - fillAmount);
            if (fillAmount == orderAmount) {
                assertEq(issuer.numOpenOrders(), 0);
                assertEq(issuer.getTotalReceived(id), 0);
            } else {
                assertEq(issuer.getTotalReceived(id), receivedAmount);
            }
        }
    }

    function testCancelOrder(uint256 orderAmount, uint256 fillAmount, string calldata reason) public {
        vm.assume(orderAmount > 0);

        OrderProcessor.OrderRequest memory order = dummyOrderRequest;
        order.quantityIn = orderAmount;
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.assetToken, order.quantityIn);
        uint256 fees = flatFee + percentageFee;
        vm.assume(fees < orderAmount);
        vm.assume(fillAmount < orderAmount - fees);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order);

        if (fillAmount > 0) {
            vm.prank(operator);
            issuer.takeEscrow(dummyOrder, fillAmount);

            vm.prank(operator);
            issuer.fillOrder(dummyOrder, fillAmount, 100);
        }

        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(dummyOrder.recipient, dummyOrder.index, reason);
        vm.prank(operator);
        issuer.cancelOrder(dummyOrder, reason);
    }

    function testCancelOrderUnreturnedEscrowReverts(uint256 orderAmount, uint256 takeAmount) public {
        vm.assume(orderAmount > 0);
        vm.assume(takeAmount > 0);

        OrderProcessor.OrderRequest memory order = dummyOrderRequest;
        order.quantityIn = orderAmount;
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.assetToken, order.quantityIn);
        uint256 fees = flatFee + percentageFee;
        vm.assume(fees < orderAmount);
        vm.assume(takeAmount < orderAmount - fees);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order);

        vm.prank(operator);
        issuer.takeEscrow(dummyOrder, takeAmount);

        vm.expectRevert(DirectBuyIssuer.UnreturnedEscrow.selector);
        vm.prank(operator);
        issuer.cancelOrder(dummyOrder, "");
    }
}
