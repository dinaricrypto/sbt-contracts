// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solady/auth/Ownable.sol";
import "solady-test/utils/mocks/MockERC20.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "../src/LimitOrderBridge.sol";
import {FlatOrderFees} from "../src/FlatOrderFees.sol";

contract LimitOrderBridgeTest is Test {
    event OrderRequested(bytes32 indexed id, address indexed user, IVaultBridge.Order order, bytes32 salt);
    event OrderFill(bytes32 indexed id, address indexed user, uint256 fillAmount);
    event OrderFulfilled(bytes32 indexed id, address indexed user, uint256 filledAmount);
    event CancelRequested(bytes32 indexed id, address indexed user);
    event OrderCancelled(bytes32 indexed id, address indexed user, string reason);

    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees orderFees);
    event PaymentTokenEnabled(address indexed token, bool enabled);
    event OrdersPaused(bool paused);

    BridgedERC20 token;
    FlatOrderFees orderFees;
    LimitOrderBridge bridge;
    MockERC20 paymentToken;

    address constant user = address(1);
    address constant bridgeOperator = address(3);
    address constant treasury = address(4);

    IVaultBridge.Order dummyOrder;
    bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;

    function setUp() public {
        token = new MockBridgedERC20();
        paymentToken = new MockERC20("Money", "$", 18);

        orderFees = new FlatOrderFees();
        orderFees.setSellerFee(0.1 ether);
        orderFees.setBuyerFee(0.1 ether);

        LimitOrderBridge bridgeImpl = new LimitOrderBridge();
        bridge = LimitOrderBridge(
            address(
                new ERC1967Proxy(address(bridgeImpl), abi.encodeCall(LimitOrderBridge.initialize, (address(this), treasury, orderFees)))
            )
        );

        token.grantRoles(address(this), token.minterRole());
        token.grantRoles(address(bridge), token.minterRole());

        bridge.setPaymentTokenEnabled(address(paymentToken), true);
        bridge.grantRoles(bridgeOperator, bridge.operatorRole());

        dummyOrder = IVaultBridge.Order({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IVaultBridge.OrderType.LIMIT,
            assetTokenQuantity: 100,
            paymentTokenQuantity: 0,
            price: 10 ether,
            tif: IVaultBridge.TIF.GTC
        });
    }

    function testInvariants() public {
        assertEq(bridge.operatorRole(), uint256(1 << 1));
    }

    function testInitialize(address owner, address newTreasury) public {
        vm.assume(owner != address(this));

        LimitOrderBridge bridgeImpl = new LimitOrderBridge();
        if (newTreasury == address(0)) {
            vm.expectRevert(LimitOrderBridge.ZeroAddress.selector);

            new ERC1967Proxy(address(bridgeImpl), abi.encodeCall(LimitOrderBridge.initialize, (owner, newTreasury, orderFees)));
            return;
        }
        LimitOrderBridge newBridge = LimitOrderBridge(
            address(
                new ERC1967Proxy(address(bridgeImpl), abi.encodeCall(LimitOrderBridge.initialize, (owner, newTreasury, orderFees)))
            )
        );
        assertEq(newBridge.owner(), owner);

        LimitOrderBridge newImpl = new LimitOrderBridge();
        vm.expectRevert(Ownable.Unauthorized.selector);
        newBridge.upgradeToAndCall(
            address(newImpl), abi.encodeCall(LimitOrderBridge.initialize, (owner, newTreasury, orderFees))
        );
    }

    function testSetTreasury(address account) public {
        if (account == address(0)) {
            vm.expectRevert(LimitOrderBridge.ZeroAddress.selector);
            bridge.setTreasury(account);
        } else {
            vm.expectEmit(true, true, true, true);
            emit TreasurySet(account);
            bridge.setTreasury(account);
            assertEq(bridge.treasury(), account);
        }
    }

    function testSetFees(IOrderFees fees) public {
        vm.expectEmit(true, true, true, true);
        emit OrderFeesSet(fees);
        bridge.setOrderFees(fees);
        assertEq(address(bridge.orderFees()), address(fees));
    }

    function testSetPaymentTokenEnabled(address account, bool enabled) public {
        vm.expectEmit(true, true, true, true);
        emit PaymentTokenEnabled(account, enabled);
        bridge.setPaymentTokenEnabled(account, enabled);
        assertEq(bridge.paymentTokenEnabled(account), enabled);
    }

    function testSetOrdersPaused(bool pause) public {
        vm.expectEmit(true, true, true, true);
        emit OrdersPaused(pause);
        bridge.setOrdersPaused(pause);
        assertEq(bridge.ordersPaused(), pause);
    }

    function testRequestOrder(
        bool sell,
        uint8 orderType,
        uint128 assetTokenQuantity,
        uint256 paymentTokenQuantity,
        uint128 price,
        uint8 tif
    ) public {
        vm.assume(orderType < 2);
        vm.assume(tif < 4);

        IVaultBridge.Order memory order = IVaultBridge.Order({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: sell,
            orderType: IVaultBridge.OrderType(orderType),
            assetTokenQuantity: assetTokenQuantity,
            paymentTokenQuantity: paymentTokenQuantity,
            price: price,
            tif: IVaultBridge.TIF(tif)
        });
        bytes32 orderId = bridge.getOrderId(order, salt);

        if (sell) {
            token.mint(user, assetTokenQuantity);
            vm.prank(user);
            token.increaseAllowance(address(bridge), assetTokenQuantity);
        } else {
            uint256 totalPayment = bridge.totalPaymentForOrder(order);
            paymentToken.mint(user, totalPayment);
            vm.prank(user);
            paymentToken.increaseAllowance(address(bridge), totalPayment);
        }

        if (orderType != 1) {
            vm.expectRevert(LimitOrderBridge.OnlyLimitOrders.selector);
            vm.prank(user);
            bridge.requestOrder(order, salt);
        } else if (assetTokenQuantity == 0) {
            vm.expectRevert(LimitOrderBridge.ZeroValue.selector);
            vm.prank(user);
            bridge.requestOrder(order, salt);
        } else if (!sell && bridge.totalPaymentForOrder(order) == 0) {
            vm.expectRevert(LimitOrderBridge.OrderTooSmall.selector);
            vm.prank(user);
            bridge.requestOrder(order, salt);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(orderId, user, order, salt);
            vm.prank(user);
            bridge.requestOrder(order, salt);
            assertTrue(bridge.isOrderActive(orderId));
            assertEq(bridge.getUnfilledAmount(orderId), assetTokenQuantity);
            assertEq(bridge.numOpenOrders(), 1);
            if (sell) {
                assertEq(bridge.getPaymentEscrow(orderId), 0);
            } else {
                assertEq(bridge.getPaymentEscrow(orderId), bridge.totalPaymentForOrder(order));
            }
        }
    }

    function testRequestOrderPausedReverts() public {
        bridge.setOrdersPaused(true);

        vm.expectRevert(LimitOrderBridge.Paused.selector);
        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);
    }

    function testRequestOrderProxyOrderReverts() public {
        vm.expectRevert(LimitOrderBridge.NoProxyOrders.selector);
        bridge.requestOrder(dummyOrder, salt);
    }

    function testRequestOrderUnsupportedPaymentReverts(address tryPaymentToken) public {
        vm.assume(!bridge.paymentTokenEnabled(tryPaymentToken));

        IVaultBridge.Order memory order = dummyOrder;
        order.paymentToken = tryPaymentToken;

        vm.expectRevert(LimitOrderBridge.UnsupportedPaymentToken.selector);
        vm.prank(user);
        bridge.requestOrder(order, salt);
    }

    function testRequestOrderCollisionReverts() public {
        paymentToken.mint(user, 10000);

        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), 10000);

        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);

        vm.expectRevert(LimitOrderBridge.DuplicateOrder.selector);
        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);
    }

    function testFillOrder(bool sell, uint128 orderAmount, uint128 price, uint128 fillAmount) public {
        vm.assume(orderAmount > 0);

        IVaultBridge.Order memory order = dummyOrder;
        order.sell = sell;
        order.assetTokenQuantity = orderAmount;
        order.price = price;
        vm.assume(sell || bridge.totalPaymentForOrder(order) > 0);

        bytes32 orderId = bridge.getOrderId(order, salt);
        uint256 proceeds = bridge.proceedsForFill(fillAmount, price);

        if (sell) {
            token.mint(user, orderAmount);
            vm.prank(user);
            token.increaseAllowance(address(bridge), orderAmount);

            paymentToken.mint(bridgeOperator, proceeds);
            vm.prank(bridgeOperator);
            paymentToken.increaseAllowance(address(bridge), proceeds);
        } else {
            uint256 totalPayment = bridge.totalPaymentForOrder(order);
            paymentToken.mint(user, totalPayment);
            vm.prank(user);
            paymentToken.increaseAllowance(address(bridge), totalPayment);
        }

        vm.prank(user);
        bridge.requestOrder(order, salt);

        if (fillAmount == 0) {
            vm.expectRevert(LimitOrderBridge.ZeroValue.selector);
            vm.prank(bridgeOperator);
            bridge.fillOrder(order, salt, fillAmount, 0);
        } else if (fillAmount > orderAmount) {
            vm.expectRevert(LimitOrderBridge.FillTooLarge.selector);
            vm.prank(bridgeOperator);
            bridge.fillOrder(order, salt, fillAmount, 0);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderFill(orderId, user, fillAmount);
            if (fillAmount == orderAmount) {
                vm.expectEmit(true, true, true, true);
                emit OrderFulfilled(orderId, user, orderAmount);
            }
            vm.prank(bridgeOperator);
            bridge.fillOrder(order, salt, fillAmount, 0);
            assertEq(bridge.getUnfilledAmount(orderId), orderAmount - fillAmount);
            if (fillAmount == orderAmount) {
                assertEq(bridge.numOpenOrders(), 0);
            }
        }
    }

    function testFillorderNoOrderReverts() public {
        vm.expectRevert(LimitOrderBridge.OrderNotFound.selector);
        vm.prank(bridgeOperator);
        bridge.fillOrder(dummyOrder, salt, 100, 100);
    }

    function testRequestCancel() public {
        uint256 totalPayment = bridge.totalPaymentForOrder(dummyOrder);
        paymentToken.mint(user, totalPayment);
        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), totalPayment);

        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);

        bytes32 orderId = bridge.getOrderId(dummyOrder, salt);
        vm.expectEmit(true, true, true, true);
        emit CancelRequested(orderId, user);
        vm.prank(user);
        bridge.requestCancel(dummyOrder, salt);
    }

    function testRequestCancelNoProxyReverts() public {
        uint256 totalPayment = bridge.totalPaymentForOrder(dummyOrder);
        paymentToken.mint(user, totalPayment);
        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), totalPayment);

        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);

        vm.expectRevert(LimitOrderBridge.NoProxyOrders.selector);
        bridge.requestCancel(dummyOrder, salt);
    }

    function testRequestCancelNotFoundReverts() public {
        vm.expectRevert(LimitOrderBridge.OrderNotFound.selector);
        vm.prank(user);
        bridge.requestCancel(dummyOrder, salt);
    }

    function testCancelOrder(uint128 orderAmount, uint128 fillAmount, string calldata reason) public {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount > 0);
        vm.assume(fillAmount < orderAmount);

        IVaultBridge.Order memory order = dummyOrder;
        order.assetTokenQuantity = orderAmount;

        uint256 totalPayment = bridge.totalPaymentForOrder(order);
        paymentToken.mint(user, totalPayment);
        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), totalPayment);

        vm.prank(user);
        bridge.requestOrder(order, salt);

        vm.prank(bridgeOperator);
        bridge.fillOrder(order, salt, fillAmount, 100);

        bytes32 orderId = bridge.getOrderId(order, salt);
        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(orderId, user, reason);
        vm.prank(bridgeOperator);
        bridge.cancelOrder(order, salt, reason);
    }

    function testCancelOrderNotFoundReverts() public {
        vm.expectRevert(LimitOrderBridge.OrderNotFound.selector);
        vm.prank(bridgeOperator);
        bridge.cancelOrder(dummyOrder, salt, "msg");
    }
}
