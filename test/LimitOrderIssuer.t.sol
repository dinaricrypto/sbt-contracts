// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solady/auth/Ownable.sol";
import "solady-test/utils/mocks/MockERC20.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "./utils/SigUtils.sol";
import "../src/LimitOrderIssuer.sol";
import {FlatOrderFees} from "../src/FlatOrderFees.sol";

contract LimitOrderIssuerTest is Test {
    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees orderFees);
    event TokenEnabled(address indexed token, bool enabled);
    event OrdersPaused(bool paused);

    event OrderRequested(bytes32 indexed id, address indexed recipient, IOrderBridge.Order order, bytes32 salt);
    event OrderFill(bytes32 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount);
    event CancelRequested(bytes32 indexed id, address indexed recipient);
    event OrderCancelled(bytes32 indexed id, address indexed recipient, string reason);

    BridgedERC20 token;
    FlatOrderFees orderFees;
    LimitOrderIssuer bridge;
    MockERC20 paymentToken;
    SigUtils paymentTokenSigUtils;
    SigUtils assetTokenSigUtils;

    uint256 userPrivateKey;
    address user;

    address constant bridgeOperator = address(3);
    address constant treasury = address(4);

    bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
    LimitOrderIssuer.LimitOrder dummyOrder;
    IOrderBridge.Order dummyOrderBridgeData;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockBridgedERC20();
        paymentToken = new MockERC20("Money", "$", 18);
        paymentTokenSigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());
        assetTokenSigUtils = new SigUtils(token.DOMAIN_SEPARATOR());

        orderFees = new FlatOrderFees();
        orderFees.setFee(0.1 ether);

        LimitOrderIssuer bridgeImpl = new LimitOrderIssuer();
        bridge = LimitOrderIssuer(
            address(
                new ERC1967Proxy(address(bridgeImpl), abi.encodeCall(LimitOrderIssuer.initialize, (address(this), treasury, orderFees)))
            )
        );

        token.grantRoles(address(this), token.minterRole());
        token.grantRoles(address(bridge), token.minterRole());

        bridge.setTokenEnabled(address(paymentToken), true);
        bridge.setTokenEnabled(address(token), true);
        bridge.grantRoles(bridgeOperator, bridge.operatorRole());

        dummyOrder = LimitOrderIssuer.LimitOrder({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            assetTokenQuantity: 100,
            price: 10 ether
        });
        dummyOrderBridgeData = IOrderBridge.Order({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderBridge.OrderType.LIMIT,
            assetTokenQuantity: dummyOrder.assetTokenQuantity,
            paymentTokenQuantity: 0,
            price: dummyOrder.price,
            tif: IOrderBridge.TIF.GTC
        });
    }

    function testInvariants() public {
        assertEq(bridge.operatorRole(), uint256(1 << 1));
    }

    function testInitialize(address owner, address newTreasury) public {
        vm.assume(owner != address(this));

        LimitOrderIssuer bridgeImpl = new LimitOrderIssuer();
        if (newTreasury == address(0)) {
            vm.expectRevert(LimitOrderIssuer.ZeroAddress.selector);

            new ERC1967Proxy(address(bridgeImpl), abi.encodeCall(LimitOrderIssuer.initialize, (owner, newTreasury, orderFees)));
            return;
        }
        LimitOrderIssuer newBridge = LimitOrderIssuer(
            address(
                new ERC1967Proxy(address(bridgeImpl), abi.encodeCall(LimitOrderIssuer.initialize, (owner, newTreasury, orderFees)))
            )
        );
        assertEq(newBridge.owner(), owner);

        LimitOrderIssuer newImpl = new LimitOrderIssuer();
        vm.expectRevert(Ownable.Unauthorized.selector);
        newBridge.upgradeToAndCall(
            address(newImpl), abi.encodeCall(LimitOrderIssuer.initialize, (owner, newTreasury, orderFees))
        );
    }

    function testSetTreasury(address account) public {
        if (account == address(0)) {
            vm.expectRevert(LimitOrderIssuer.ZeroAddress.selector);
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

    function testSetTokenEnabled(address account, bool enabled) public {
        vm.expectEmit(true, true, true, true);
        emit TokenEnabled(account, enabled);
        bridge.setTokenEnabled(account, enabled);
        assertEq(bridge.tokenEnabled(account), enabled);
    }

    function testSetOrdersPaused(bool pause) public {
        vm.expectEmit(true, true, true, true);
        emit OrdersPaused(pause);
        bridge.setOrdersPaused(pause);
        assertEq(bridge.ordersPaused(), pause);
    }

    function testRequestOrder(bool sell, uint128 assetTokenQuantity, uint128 price) public {
        LimitOrderIssuer.LimitOrder memory order = LimitOrderIssuer.LimitOrder({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: sell,
            assetTokenQuantity: assetTokenQuantity,
            price: price
        });

        IOrderBridge.Order memory orderBridgeData = IOrderBridge.Order({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: sell,
            orderType: IOrderBridge.OrderType.LIMIT,
            assetTokenQuantity: assetTokenQuantity,
            paymentTokenQuantity: 0,
            price: price,
            tif: IOrderBridge.TIF.GTC
        });
        bytes32 orderId = bridge.getOrderId(order, salt);

        (uint256 fees, uint256 value) =
            bridge.getFeesForOrder(order.assetToken, order.sell, order.assetTokenQuantity, order.price);
        uint256 totalPayment = fees + value;

        if (sell) {
            token.mint(user, assetTokenQuantity);
            vm.prank(user);
            token.increaseAllowance(address(bridge), assetTokenQuantity);
        } else {
            paymentToken.mint(user, totalPayment);
            vm.prank(user);
            paymentToken.increaseAllowance(address(bridge), totalPayment);
        }

        if (assetTokenQuantity == 0) {
            vm.expectRevert(LimitOrderIssuer.ZeroValue.selector);
            vm.prank(user);
            bridge.requestOrder(order, salt);
        } else if (!sell && totalPayment == 0) {
            vm.expectRevert(LimitOrderIssuer.OrderTooSmall.selector);
            vm.prank(user);
            bridge.requestOrder(order, salt);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(orderId, user, orderBridgeData, salt);
            vm.prank(user);
            bridge.requestOrder(order, salt);
            assertTrue(bridge.isOrderActive(orderId));
            assertEq(bridge.getUnfilledAmount(orderId), assetTokenQuantity);
            assertEq(bridge.numOpenOrders(), 1);
            if (sell) {
                assertEq(bridge.getPaymentEscrow(orderId), 0);
            } else {
                assertEq(bridge.getPaymentEscrow(orderId), totalPayment);
            }
        }
    }

    function testRequestOrderPausedReverts() public {
        bridge.setOrdersPaused(true);

        vm.expectRevert(LimitOrderIssuer.Paused.selector);
        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);
    }

    function testRequestOrderUnsupportedPaymentReverts(address tryPaymentToken) public {
        vm.assume(!bridge.tokenEnabled(tryPaymentToken));

        LimitOrderIssuer.LimitOrder memory order = dummyOrder;
        order.paymentToken = tryPaymentToken;

        vm.expectRevert(LimitOrderIssuer.UnsupportedToken.selector);
        vm.prank(user);
        bridge.requestOrder(order, salt);
    }

    function testRequestOrderUnsupportedAssetReverts(address tryAssetToken) public {
        vm.assume(!bridge.tokenEnabled(tryAssetToken));

        LimitOrderIssuer.LimitOrder memory order = dummyOrder;
        order.assetToken = tryAssetToken;

        vm.expectRevert(LimitOrderIssuer.UnsupportedToken.selector);
        vm.prank(user);
        bridge.requestOrder(order, salt);
    }

    function testRequestOrderCollisionReverts() public {
        paymentToken.mint(user, 10000);

        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), 10000);

        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);

        vm.expectRevert(LimitOrderIssuer.DuplicateOrder.selector);
        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);
    }

    function testRequestOrderWithPermit(bool sell) public {
        LimitOrderIssuer.LimitOrder memory order = dummyOrder;
        order.sell = sell;
        bytes32 orderId = bridge.getOrderId(order, salt);
        (uint256 fees, uint256 value) =
            bridge.getFeesForOrder(order.assetToken, order.sell, order.assetTokenQuantity, order.price);
        uint256 totalPayment = fees + value;

        SigUtils.Permit memory permit;
        bytes32 digest;
        if (sell) {
            token.mint(user, order.assetTokenQuantity);

            permit = SigUtils.Permit({
                owner: user,
                spender: address(bridge),
                value: order.assetTokenQuantity,
                nonce: 0,
                deadline: 30 days
            });

            digest = assetTokenSigUtils.getTypedDataHash(permit);
        } else {
            paymentToken.mint(user, totalPayment);

            permit = SigUtils.Permit({
                owner: user,
                spender: address(bridge),
                value: totalPayment,
                nonce: 0,
                deadline: 30 days
            });

            digest = paymentTokenSigUtils.getTypedDataHash(permit);
        }

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        IOrderBridge.Order memory orderBridgeData = IOrderBridge.Order({
            recipient: order.recipient,
            assetToken: order.assetToken,
            paymentToken: order.paymentToken,
            sell: sell,
            orderType: IOrderBridge.OrderType.LIMIT,
            assetTokenQuantity: order.assetTokenQuantity,
            paymentTokenQuantity: 0,
            price: order.price,
            tif: IOrderBridge.TIF.GTC
        });
        vm.expectEmit(true, true, true, true);
        emit OrderRequested(orderId, user, orderBridgeData, salt);
        vm.prank(user);
        bridge.requestOrderWithPermit(order, salt, permit.value, permit.deadline, v, r, s);
        assertTrue(bridge.isOrderActive(orderId));
        assertEq(bridge.getUnfilledAmount(orderId), order.assetTokenQuantity);
        assertEq(bridge.numOpenOrders(), 1);
        if (sell) {
            assertEq(token.nonces(user), 1);
            assertEq(token.allowance(user, address(bridge)), 0);
            assertEq(bridge.getPaymentEscrow(orderId), 0);
        } else {
            assertEq(paymentToken.nonces(user), 1);
            assertEq(paymentToken.allowance(user, address(bridge)), 0);
            assertEq(bridge.getPaymentEscrow(orderId), totalPayment);
        }
    }

    function testFillOrder(bool sell, uint128 orderAmount, uint128 price, uint128 fillAmount) public {
        vm.assume(orderAmount > 0);

        LimitOrderIssuer.LimitOrder memory order = dummyOrder;
        order.sell = sell;
        order.assetTokenQuantity = orderAmount;
        order.price = price;
        (uint256 fees, uint256 value) =
            bridge.getFeesForOrder(order.assetToken, order.sell, order.assetTokenQuantity, order.price);
        uint256 totalPayment = fees + value;
        vm.assume(sell || totalPayment > 0);

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
            paymentToken.mint(user, totalPayment);
            vm.prank(user);
            paymentToken.increaseAllowance(address(bridge), totalPayment);
        }

        vm.prank(user);
        bridge.requestOrder(order, salt);

        if (fillAmount == 0) {
            vm.expectRevert(LimitOrderIssuer.ZeroValue.selector);
            vm.prank(bridgeOperator);
            bridge.fillOrder(order, salt, fillAmount, 0);
        } else if (fillAmount > orderAmount) {
            vm.expectRevert(LimitOrderIssuer.FillTooLarge.selector);
            vm.prank(bridgeOperator);
            bridge.fillOrder(order, salt, fillAmount, 0);
        } else {
            vm.expectEmit(true, true, true, false);
            emit OrderFill(orderId, user, fillAmount, 0);
            vm.prank(bridgeOperator);
            bridge.fillOrder(order, salt, fillAmount, 10);
            assertEq(bridge.getUnfilledAmount(orderId), orderAmount - fillAmount);
            if (fillAmount == orderAmount) {
                assertEq(bridge.numOpenOrders(), 0);
            }
        }
    }

    function testFillorderNoOrderReverts() public {
        vm.expectRevert(LimitOrderIssuer.OrderNotFound.selector);
        vm.prank(bridgeOperator);
        bridge.fillOrder(dummyOrder, salt, 100, 100);
    }

    function testRequestCancel() public {
        (uint256 fees, uint256 value) = bridge.getFeesForOrder(
            dummyOrder.assetToken, dummyOrder.sell, dummyOrder.assetTokenQuantity, dummyOrder.price
        );
        uint256 totalPayment = fees + value;
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

    function testRequestCancelNotRecipientReverts() public {
        (uint256 fees, uint256 value) = bridge.getFeesForOrder(
            dummyOrder.assetToken, dummyOrder.sell, dummyOrder.assetTokenQuantity, dummyOrder.price
        );
        uint256 totalPayment = fees + value;
        paymentToken.mint(user, totalPayment);
        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), totalPayment);

        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);

        vm.expectRevert(LimitOrderIssuer.NotRecipient.selector);
        bridge.requestCancel(dummyOrder, salt);
    }

    function testRequestCancelNotFoundReverts() public {
        vm.expectRevert(LimitOrderIssuer.OrderNotFound.selector);
        vm.prank(user);
        bridge.requestCancel(dummyOrder, salt);
    }

    function testCancelOrder(uint128 orderAmount, uint128 fillAmount, string calldata reason) public {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount > 0);
        vm.assume(fillAmount < orderAmount);

        LimitOrderIssuer.LimitOrder memory order = dummyOrder;
        order.assetTokenQuantity = orderAmount;

        (uint256 fees, uint256 value) =
            bridge.getFeesForOrder(order.assetToken, order.sell, order.assetTokenQuantity, order.price);
        uint256 totalPayment = fees + value;
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
        vm.expectRevert(LimitOrderIssuer.OrderNotFound.selector);
        vm.prank(bridgeOperator);
        bridge.cancelOrder(dummyOrder, salt, "msg");
    }
}