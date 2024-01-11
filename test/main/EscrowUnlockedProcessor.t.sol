// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {MockToken} from "../utils/mocks/MockToken.sol";
import "../utils/mocks/MockDShareFactory.sol";
import "../../src/orders/OrderProcessor.sol";
import {TokenLockCheck, ITokenLockCheck} from "../../src/TokenLockCheck.sol";
import {NumberUtils} from "../../src/common/NumberUtils.sol";
import "prb-math/Common.sol" as PrbMath;
import {FeeLib} from "../../src/common/FeeLib.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract EscrowUnlockedProcessorTest is Test {
    event EscrowTaken(uint256 indexed id, address indexed recipient, uint256 amount);
    event EscrowReturned(uint256 indexed id, address indexed recipient, uint256 amount);

    event OrderFill(
        uint256 indexed id,
        address indexed requester,
        address paymentToken,
        address assetToken,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256 feesPaid
    );
    event OrderCancelled(uint256 indexed id, address indexed recipient, string reason);

    MockDShareFactory tokenFactory;
    DShare token;
    TokenLockCheck tokenLockCheck;
    OrderProcessor issuer;
    MockToken paymentToken;

    uint256 userPrivateKey;
    uint256 adminPrivateKey;
    address user;
    address admin;

    address constant operator = address(3);
    address constant treasury = address(4);

    uint256 flatFee;
    uint24 percentageFeeRate;
    uint256 dummyOrderFees;
    IOrderProcessor.Order dummyOrder;

    function setUp() public {
        userPrivateKey = 0x01;
        adminPrivateKey = 0x02;
        user = vm.addr(userPrivateKey);
        admin = vm.addr(adminPrivateKey);

        vm.startPrank(admin);
        tokenFactory = new MockDShareFactory();
        token = tokenFactory.deploy("Dinari Token", "dTKN");
        paymentToken = new MockToken("Money", "$");

        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(paymentToken));

        OrderProcessor issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl),
                    abi.encodeCall(OrderProcessor.initialize, (admin, treasury, tokenLockCheck, address(1)))
                )
            )
        );

        token.grantRole(token.MINTER_ROLE(), admin);
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        OrderProcessor.FeeRates memory defaultFees = OrderProcessor.FeeRates({
            perOrderFeeBuy: 1 ether,
            percentageFeeRateBuy: 5_000,
            perOrderFeeSell: 1 ether,
            percentageFeeRateSell: 5_000
        });
        issuer.setDefaultFees(address(paymentToken), defaultFees);
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);

        vm.stopPrank();

        (flatFee, percentageFeeRate) = issuer.getFeeRatesForOrder(user, false, address(paymentToken));
        dummyOrderFees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, 100 ether);
        dummyOrder = IOrderProcessor.Order({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 100 ether,
            price: 0,
            tif: IOrderProcessor.TIF.GTC,
            escrowUnlocked: true
        });
    }

    function testTakeEscrow(uint256 orderAmount, uint256 takeAmount) public {
        vm.assume(orderAmount > 0);
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderProcessor.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;

        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        vm.prank(user);
        uint256 id = issuer.requestOrder(order);

        if (takeAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.takeEscrow(id, order, takeAmount);
        } else if (takeAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.takeEscrow(id, order, takeAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit EscrowTaken(id, user, takeAmount);
            vm.prank(operator);
            issuer.takeEscrow(id, order, takeAmount);
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
        order.paymentTokenQuantity = orderAmount;

        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        vm.prank(user);
        uint256 id = issuer.requestOrder(order);

        vm.prank(operator);
        issuer.takeEscrow(id, order, orderAmount);

        vm.prank(operator);
        paymentToken.approve(address(issuer), returnAmount);

        if (returnAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.returnEscrow(id, order, returnAmount);
        } else if (returnAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.returnEscrow(id, order, returnAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit EscrowReturned(id, user, returnAmount);
            vm.prank(operator);
            issuer.returnEscrow(id, order, returnAmount);
            assertEq(issuer.getOrderEscrow(id), returnAmount);
            assertEq(paymentToken.balanceOf(address(issuer)), fees + returnAmount);
        }
    }

    function testFillOrder(uint256 orderAmount, uint256 takeAmount, uint256 fillAmount, uint256 receivedAmount)
        public
    {
        vm.assume(takeAmount > 0);
        vm.assume(takeAmount <= orderAmount);
        vm.assume(fillAmount > 0);
        vm.assume(fillAmount <= takeAmount);
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderProcessor.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;

        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        vm.prank(user);
        uint256 id = issuer.requestOrder(order);

        vm.prank(operator);
        issuer.takeEscrow(id, order, takeAmount);

        vm.expectEmit(true, true, true, false);
        // since we can't capture the function var without rewritting the _fillOrderAccounting inside the test
        emit OrderFill(id, order.recipient, order.paymentToken, order.assetToken, fillAmount, receivedAmount, 0);
        vm.prank(operator);
        issuer.fillOrder(id, order, fillAmount, receivedAmount);
        assertEq(issuer.getUnfilledAmount(id), orderAmount - fillAmount);
        if (fillAmount == orderAmount) {
            assertEq(issuer.numOpenOrders(), 0);
            assertEq(issuer.getTotalReceived(id), 0);
            assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.FULFILLED));
        } else {
            assertEq(issuer.getTotalReceived(id), receivedAmount);
            assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        }
    }

    // Useful case: 1000003, 1, ''
    // Useful case: 1000003, 1, ''
    function testCancelOrder(uint256 orderAmount, uint256 fillAmount, string calldata reason, uint256 _price) public {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount < orderAmount);
        vm.assume(_price > 0);
        vm.assume(!NumberUtils.mulDivCheckOverflow(fillAmount, 1 ether, _price));
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;
        uint256 receivedAmount = PrbMath.mulDiv(fillAmount, 1 ether, _price);

        IOrderProcessor.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;
        order.price = _price;

        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        vm.prank(user);
        uint256 id = issuer.requestOrder(order);

        if (fillAmount > 0) {
            vm.prank(operator);
            issuer.takeEscrow(id, order, fillAmount);

            vm.prank(operator);
            issuer.fillOrder(id, order, fillAmount, receivedAmount);
        }

        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(id, order.recipient, reason);
        vm.prank(operator);
        issuer.cancelOrder(id, order, reason);
        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.CANCELLED));
    }

    function testCancelOrderUnreturnedEscrowReverts(uint256 orderAmount, uint256 takeAmount) public {
        vm.assume(orderAmount > 0);
        vm.assume(takeAmount > 0);
        vm.assume(takeAmount < orderAmount);
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderProcessor.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;

        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        vm.prank(user);
        uint256 id = issuer.requestOrder(order);

        vm.prank(operator);
        issuer.takeEscrow(id, order, takeAmount);

        vm.expectRevert(OrderProcessor.UnreturnedEscrow.selector);
        vm.prank(operator);
        issuer.cancelOrder(id, order, "");
    }
}
