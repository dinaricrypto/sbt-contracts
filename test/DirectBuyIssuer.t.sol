// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";
import "./utils/mocks/MockdShare.sol";
import "../src/issuer/DirectBuyIssuer.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import {TokenLockCheck, ITokenLockCheck} from "../src/TokenLockCheck.sol";
import {NumberUtils} from "./utils/NumberUtils.sol";
import "prb-math/Common.sol" as PrbMath;
import {FeeLib} from "../src/FeeLib.sol";

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
    uint24 percentageFeeRate;
    uint256 dummyOrderFees;
    IOrderBridge.Order dummyOrder;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockdShare();
        paymentToken = new MockToken();

        orderFees = new OrderFees(address(this), 1 ether, 5_000);

        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(paymentToken));

        issuer = new DirectBuyIssuer(address(this), treasury, orderFees, tokenLockCheck);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);

        (flatFee, percentageFeeRate) = issuer.getFeeRatesForOrder(address(paymentToken));
        dummyOrderFees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, 100 ether);
        dummyOrder = IOrderBridge.Order({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderBridge.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 100 ether,
            price: 0,
            tif: IOrderBridge.TIF.GTC
        });
    }

    function testTakeEscrow(uint256 orderAmount, uint256 takeAmount) public {
        vm.assume(orderAmount > 0);
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderBridge.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.prank(user);
        uint256 index = issuer.requestOrder(order);

        bytes32 id = issuer.getOrderId(order.recipient, index);

        if (takeAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.takeEscrow(order, index, takeAmount);
        } else if (takeAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.takeEscrow(order, index, takeAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit EscrowTaken(order.recipient, index, takeAmount);
            vm.prank(operator);
            issuer.takeEscrow(order, index, takeAmount);
            assertEq(paymentToken.balanceOf(operator), takeAmount);
            assertEq(issuer.getOrderEscrow(id), orderAmount - takeAmount);
        }
    }

    function testReturnEscrow(uint256 orderAmount, uint256 returnAmount) public {
        vm.assume(orderAmount > 0);
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderBridge.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.prank(user);
        uint256 index = issuer.requestOrder(order);

        vm.prank(operator);
        issuer.takeEscrow(order, index, orderAmount);

        vm.prank(operator);
        paymentToken.increaseAllowance(address(issuer), returnAmount);

        bytes32 id = issuer.getOrderId(order.recipient, index);

        if (returnAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.returnEscrow(order, index, returnAmount);
        } else if (returnAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.returnEscrow(order, index, returnAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit EscrowReturned(order.recipient, index, returnAmount);
            vm.prank(operator);
            issuer.returnEscrow(order, index, returnAmount);
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

        IOrderBridge.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.prank(user);
        uint256 index = issuer.requestOrder(order);

        vm.prank(operator);
        issuer.takeEscrow(order, index, takeAmount);

        bytes32 id = issuer.getOrderId(order.recipient, index);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, index, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount || fillAmount > takeAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, index, fillAmount, receivedAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderFill(order.recipient, index, fillAmount, receivedAmount);
            vm.prank(operator);
            issuer.fillOrder(order, index, fillAmount, receivedAmount);
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

        IOrderBridge.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.prank(user);
        uint256 index = issuer.requestOrder(order);

        if (fillAmount > 0) {
            vm.prank(operator);
            issuer.takeEscrow(order, index, fillAmount);

            vm.prank(operator);
            issuer.fillOrder(order, index, fillAmount, receivedAmount);
        }

        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(order.recipient, index, reason);
        vm.prank(operator);
        issuer.cancelOrder(order, index, reason);
    }

    function testCancelOrderUnreturnedEscrowReverts(uint256 orderAmount, uint256 takeAmount) public {
        vm.assume(orderAmount > 0);
        vm.assume(takeAmount > 0);
        vm.assume(takeAmount < orderAmount);
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderBridge.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.prank(user);
        uint256 index = issuer.requestOrder(order);

        vm.prank(operator);
        issuer.takeEscrow(order, index, takeAmount);

        vm.expectRevert(DirectBuyIssuer.UnreturnedEscrow.selector);
        vm.prank(operator);
        issuer.cancelOrder(order, index, "");
    }
}
