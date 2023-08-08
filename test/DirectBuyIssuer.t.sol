// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";
import "./utils/mocks/MockdShare.sol";
import "../src/issuer/DirectBuyIssuer.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import {TokenLockCheck, ITokenLockCheck} from "../src/TokenLockCheck.sol";

contract DirectBuyIssuerTest is Test {
    event EscrowTaken(address indexed recipient, uint256 indexed index, uint256 amount);
    event EscrowReturned(address indexed recipient, uint256 indexed index, uint256 amount);

    event OrderRequested(address indexed recipient, uint256 indexed index, IOrderBridge.Order order);
    event OrderFill(address indexed recipient, uint256 indexed index, uint256 fillAmount, uint256 receivedAmount);
    event OrderFulfilled(address indexed recipient, uint256 indexed index);
    event CancelRequested(address indexed recipient, uint256 indexed index);
    event OrderCancelled(address indexed recipient, uint256 indexed index, string reason);

    dShare token;
    OrderFees orderFees;
    TokenLockCheck tokenLockCheck;
    DirectBuyIssuer issuer;
    MockToken paymentToken;

    uint256 userPrivateKey;
    address user;

    address constant operator = address(3);
    address constant treasury = address(4);

    uint256 flatFee;
    uint64 percentageFeeRate;
    IOrderBridge.OrderRequest dummyOrderRequest;
    uint256 dummyOrderFees;
    IOrderBridge.Order dummyOrder;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockdShare();
        paymentToken = new MockToken();

        orderFees = new OrderFees(address(this), 1 ether, 0.005 ether);

        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(paymentToken));
        issuer = new DirectBuyIssuer(address(this), treasury, orderFees, tokenLockCheck);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);

        dummyOrderRequest = IOrderBridge.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: 100 ether,
            price: 0
        });
        (flatFee, percentageFeeRate) = issuer.getFeeRatesForOrder(address(paymentToken));
        dummyOrderFees = issuer.estimateTotalFees(flatFee, percentageFeeRate, dummyOrderRequest.quantityIn);
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

        IOrderBridge.OrderRequest memory orderRequest = dummyOrderRequest;
        orderRequest.quantityIn = orderAmount;

        uint256 fees = issuer.estimateTotalFees(flatFee, percentageFeeRate, orderRequest.quantityIn);
        vm.assume(fees < orderAmount);

        IOrderBridge.Order memory order = dummyOrder;
        order.quantityIn = orderAmount;
        order.paymentTokenQuantity = orderAmount - fees;

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);

        vm.prank(user);
        issuer.requestOrder(orderRequest);

        if (takeAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.takeEscrow(order, takeAmount);
        } else if (takeAmount > orderAmount - fees) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.takeEscrow(order, takeAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit EscrowTaken(order.recipient, order.index, takeAmount);
            vm.prank(operator);
            issuer.takeEscrow(order, takeAmount);
            assertEq(paymentToken.balanceOf(operator), takeAmount);
            assertEq(issuer.getOrderEscrow(id), orderAmount - fees - takeAmount);
        }
    }

    function testReturnEscrow(uint256 orderAmount, uint256 returnAmount) public {
        vm.assume(orderAmount > 0);

        IOrderBridge.OrderRequest memory orderRequest = dummyOrderRequest;
        orderRequest.quantityIn = orderAmount;
        uint256 fees = issuer.estimateTotalFees(flatFee, percentageFeeRate, orderRequest.quantityIn);
        vm.assume(fees < orderAmount);

        IOrderBridge.Order memory order = dummyOrder;
        order.quantityIn = orderAmount;
        order.paymentTokenQuantity = orderAmount - fees;

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(orderRequest);

        uint256 takeAmount = orderAmount - fees;
        vm.prank(operator);
        issuer.takeEscrow(order, takeAmount);

        vm.prank(operator);
        paymentToken.increaseAllowance(address(issuer), returnAmount);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);

        if (returnAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.returnEscrow(order, returnAmount);
        } else if (returnAmount > takeAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.returnEscrow(order, returnAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit EscrowReturned(order.recipient, order.index, returnAmount);
            vm.prank(operator);
            issuer.returnEscrow(order, returnAmount);
            assertEq(issuer.getOrderEscrow(id), returnAmount);
            assertEq(paymentToken.balanceOf(address(issuer)), fees + returnAmount);
        }
    }

    function testFillOrder(uint256 orderAmount, uint256 takeAmount, uint256 fillAmount, uint256 receivedAmount)
        public
    {
        vm.assume(takeAmount > 0);

        IOrderBridge.OrderRequest memory orderRequest = dummyOrderRequest;
        orderRequest.quantityIn = orderAmount;
        uint256 fees = issuer.estimateTotalFees(flatFee, percentageFeeRate, orderRequest.quantityIn);
        vm.assume(fees <= orderAmount);
        vm.assume(takeAmount <= orderAmount - fees);

        IOrderBridge.Order memory order = dummyOrder;
        order.quantityIn = orderAmount;
        order.paymentTokenQuantity = orderAmount - fees;

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(orderRequest);

        vm.prank(operator);
        issuer.takeEscrow(order, takeAmount);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount - fees || fillAmount > takeAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderFill(order.recipient, order.index, fillAmount, receivedAmount);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
            assertEq(issuer.getRemainingOrder(id), orderAmount - fees - fillAmount);
            if (fillAmount == orderAmount) {
                assertEq(issuer.numOpenOrders(), 0);
                assertEq(issuer.getTotalReceived(id), 0);
            } else {
                assertEq(issuer.getTotalReceived(id), receivedAmount);
            }
        }
    }

    // Useful case: 1000003, 1, ''
    function testCancelOrder(uint256 orderAmount, uint256 fillAmount, string calldata reason) public {
        vm.assume(orderAmount > 0);

        IOrderBridge.OrderRequest memory orderRequest = dummyOrderRequest;
        orderRequest.quantityIn = orderAmount;
        uint256 fees = issuer.estimateTotalFees(flatFee, percentageFeeRate, orderRequest.quantityIn);
        vm.assume(fees < orderAmount);
        vm.assume(fillAmount < orderAmount - fees);

        IOrderBridge.Order memory order = dummyOrder;
        order.quantityIn = orderAmount;
        order.paymentTokenQuantity = orderAmount - fees;

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(orderRequest);

        if (fillAmount > 0) {
            vm.prank(operator);
            issuer.takeEscrow(order, fillAmount);

            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, 100);
        }

        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(order.recipient, order.index, reason);
        vm.prank(operator);
        issuer.cancelOrder(order, reason);
    }

    function testCancelOrderUnreturnedEscrowReverts(uint256 orderAmount, uint256 takeAmount) public {
        vm.assume(orderAmount > 0);
        vm.assume(takeAmount > 0);

        IOrderBridge.OrderRequest memory orderRequest = dummyOrderRequest;
        orderRequest.quantityIn = orderAmount;
        uint256 fees = issuer.estimateTotalFees(flatFee, percentageFeeRate, orderRequest.quantityIn);
        vm.assume(fees < orderAmount);
        vm.assume(takeAmount < orderAmount - fees);

        IOrderBridge.Order memory order = dummyOrder;
        order.quantityIn = orderAmount;
        order.paymentTokenQuantity = orderAmount - fees;

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(orderRequest);

        vm.prank(operator);
        issuer.takeEscrow(order, takeAmount);

        vm.expectRevert(DirectBuyIssuer.UnreturnedEscrow.selector);
        vm.prank(operator);
        issuer.cancelOrder(order, "");
    }
}
