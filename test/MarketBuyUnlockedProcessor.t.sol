// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";
import "./utils/mocks/MockdShare.sol";
import "../src/orders/MarketBuyUnlockedProcessor.sol";
import "../src/orders/IOrderProcessor.sol";
import {OrderFees, IOrderFees} from "../src/orders/OrderFees.sol";
import {TokenLockCheck, ITokenLockCheck} from "../src/TokenLockCheck.sol";
import {NumberUtils} from "./utils/NumberUtils.sol";
import "prb-math/Common.sol" as PrbMath;
import {FeeLib} from "../src/FeeLib.sol";

contract MarketBuyUnlockedProcessorTest is Test {
    event EscrowTaken(address indexed recipient, uint256 indexed index, uint256 amount);
    event EscrowReturned(address indexed recipient, uint256 indexed index, uint256 amount);

    event OrderRequested(address indexed recipient, uint256 indexed index, IOrderProcessor.Order order);
    event OrderFill(address indexed recipient, uint256 indexed index, uint256 fillAmount, uint256 receivedAmount);
    event OrderFulfilled(address indexed recipient, uint256 indexed index);
    event CancelRequested(address indexed recipient, uint256 indexed index);
    event OrderCancelled(address indexed recipient, uint256 indexed index, string reason);

    dShare token;
    OrderFees orderFees;
    TokenLockCheck tokenLockCheck;
    MarketBuyUnlockedProcessor issuer;
    MockToken paymentToken;

    uint256 userPrivateKey;
    address user;

    address constant operator = address(3);
    address constant treasury = address(4);

    uint256 flatFee;
    uint24 percentageFeeRate;
    uint256 dummyOrderFees;
    IOrderProcessor.Order dummyOrder;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockdShare();
        paymentToken = new MockToken();

        orderFees = new OrderFees(address(this), 1 ether, 5_000);

        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(paymentToken));

        issuer = new MarketBuyUnlockedProcessor(address(this), treasury, orderFees, tokenLockCheck);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);

        (flatFee, percentageFeeRate) = issuer.getFeeRatesForOrder(address(paymentToken));
        dummyOrderFees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, 100 ether);
        dummyOrder = IOrderProcessor.Order({
            recipient: user,
            index: 0,
            quantityIn: 100 ether + dummyOrderFees,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 100 ether,
            price: 0,
            tif: IOrderProcessor.TIF.GTC
        });
    }

    function testTakeEscrow(uint256 orderAmount, uint256 takeAmount) public {
        vm.assume(orderAmount > 0);
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderProcessor.Order memory order = dummyOrder;
        order.quantityIn = quantityIn;
        order.paymentTokenQuantity = orderAmount;

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);

        vm.prank(user);
        issuer.requestOrder(order);

        if (takeAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.takeEscrow(order, takeAmount);
        } else if (takeAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.takeEscrow(order, takeAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit EscrowTaken(order.recipient, order.index, takeAmount);
            vm.prank(operator);
            issuer.takeEscrow(order, takeAmount);
            assertEq(paymentToken.balanceOf(operator), takeAmount);
            assertEq(issuer.getOrderEscrow(id), orderAmount - takeAmount);
        }
    }

    function testReturnEscrow(uint256 orderAmount, uint256 returnAmount) public {
        vm.assume(orderAmount > 0);
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderProcessor.Order memory order = dummyOrder;
        order.quantityIn = quantityIn;
        order.paymentTokenQuantity = orderAmount;

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.prank(user);
        issuer.requestOrder(order);

        vm.prank(operator);
        issuer.takeEscrow(order, orderAmount);

        vm.prank(operator);
        paymentToken.increaseAllowance(address(issuer), returnAmount);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);

        if (returnAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.returnEscrow(order, returnAmount);
        } else if (returnAmount > orderAmount) {
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
        vm.assume(takeAmount <= orderAmount);
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderProcessor.Order memory order = dummyOrder;
        order.quantityIn = quantityIn;
        order.paymentTokenQuantity = orderAmount;

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.prank(user);
        issuer.requestOrder(order);

        vm.prank(operator);
        issuer.takeEscrow(order, takeAmount);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount || fillAmount > takeAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderFill(order.recipient, order.index, fillAmount, receivedAmount);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
            assertEq(issuer.getRemainingOrder(id), orderAmount - fillAmount);
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
        vm.assume(fillAmount < orderAmount);
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderProcessor.Order memory order = dummyOrder;
        order.quantityIn = quantityIn;
        order.paymentTokenQuantity = orderAmount;

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.prank(user);
        issuer.requestOrder(order);

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
        vm.assume(takeAmount < orderAmount);
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderProcessor.Order memory order = dummyOrder;
        order.quantityIn = quantityIn;
        order.paymentTokenQuantity = orderAmount;

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.prank(user);
        issuer.requestOrder(order);

        vm.prank(operator);
        issuer.takeEscrow(order, takeAmount);

        vm.expectRevert(MarketBuyUnlockedProcessor.UnreturnedEscrow.selector);
        vm.prank(operator);
        issuer.cancelOrder(order, "");
    }
}
