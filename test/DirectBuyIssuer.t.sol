// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solady-test/utils/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "./utils/SigUtils.sol";
import "../src/issuer/DirectBuyIssuer.sol";
import {FlatOrderFees} from "../src/FlatOrderFees.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract DirectBuyIssuerTest is Test {
    event OrderTaken(bytes32 indexed orderId, address indexed recipient, uint256 amount);
    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees orderFees);
    event OrdersPaused(bool paused);

    event OrderRequested(bytes32 indexed id, address indexed recipient, IOrderBridge.Order order, bytes32 salt);
    event OrderFill(bytes32 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount);
    event CancelRequested(bytes32 indexed id, address indexed recipient);
    event OrderCancelled(bytes32 indexed id, address indexed recipient, string reason);

    BridgedERC20 token;
    FlatOrderFees orderFees;
    DirectBuyIssuer issuer;
    MockERC20 paymentToken;
    SigUtils sigUtils;

    uint256 userPrivateKey;
    address user;

    address constant operator = address(3);
    address constant treasury = address(4);

    bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
    DirectBuyIssuer.BuyOrder dummyOrder;
    uint256 dummyOrderFees;
    IOrderBridge.Order dummyOrderBridgeData;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockBridgedERC20();
        paymentToken = new MockERC20("Money", "$", 18);
        sigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());

        orderFees = new FlatOrderFees(address(this), 0.005 ether);

        DirectBuyIssuer issuerImpl = new DirectBuyIssuer();
        issuer = DirectBuyIssuer(
            address(
                new ERC1967Proxy(address(issuerImpl), abi.encodeCall(issuerImpl.initialize, (address(this), treasury, orderFees)))
            )
        );

        token.setMinter(address(this), true);
        token.setMinter(address(issuer), true);

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);

        dummyOrder = DirectBuyIssuer.BuyOrder({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: 100
        });
        dummyOrderFees = issuer.getFeesForOrder(dummyOrder.assetToken, false, dummyOrder.quantityIn);
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

    function testInitialize(address owner, address newTreasury) public {
        vm.assume(owner != address(this));

        DirectBuyIssuer issuerImpl = new DirectBuyIssuer();
        if (owner == address(0)) {
            vm.expectRevert("AccessControl: 0 default admin");

            new ERC1967Proxy(address(issuerImpl), abi.encodeCall(issuerImpl.initialize, (owner, newTreasury, orderFees)));
        } else if (newTreasury == address(0)) {
            vm.expectRevert(Issuer.ZeroAddress.selector);

            new ERC1967Proxy(address(issuerImpl), abi.encodeCall(issuerImpl.initialize, (owner, newTreasury, orderFees)));
        } else {
            DirectBuyIssuer newIssuer = DirectBuyIssuer(
                address(
                    new ERC1967Proxy(address(issuerImpl), abi.encodeCall(issuerImpl.initialize, (owner, newTreasury, orderFees)))
                )
            );
            assertEq(newIssuer.owner(), owner);

            DirectBuyIssuer newImpl = new DirectBuyIssuer();
            vm.expectRevert(
                bytes.concat(
                    "AccessControl: account ",
                    bytes(Strings.toHexString(address(this))),
                    " is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
                )
            );
            newIssuer.upgradeToAndCall(
                address(newImpl), abi.encodeCall(newImpl.initialize, (owner, newTreasury, orderFees))
            );
        }
    }

    function testSetTreasury(address account) public {
        if (account == address(0)) {
            vm.expectRevert(Issuer.ZeroAddress.selector);
            issuer.setTreasury(account);
        } else {
            vm.expectEmit(true, true, true, true);
            emit TreasurySet(account);
            issuer.setTreasury(account);
            assertEq(issuer.treasury(), account);
        }
    }

    function testSetFees(IOrderFees fees) public {
        vm.expectEmit(true, true, true, true);
        emit OrderFeesSet(fees);
        issuer.setOrderFees(fees);
        assertEq(address(issuer.orderFees()), address(fees));
    }

    function testSetOrdersPaused(bool pause) public {
        vm.expectEmit(true, true, true, true);
        emit OrdersPaused(pause);
        issuer.setOrdersPaused(pause);
        assertEq(issuer.ordersPaused(), pause);
    }

    function testRequestOrder(uint128 quantityIn) public {
        DirectBuyIssuer.BuyOrder memory order = DirectBuyIssuer.BuyOrder({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: quantityIn
        });
        bytes32 orderId = issuer.getOrderIdFromBuyOrder(order, salt);

        uint256 fees = issuer.getFeesForOrder(order.assetToken, false, order.quantityIn);
        IOrderBridge.Order memory bridgeOrderData = IOrderBridge.Order({
            recipient: order.recipient,
            assetToken: order.assetToken,
            paymentToken: order.paymentToken,
            sell: false,
            orderType: IOrderBridge.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 0,
            price: 0,
            tif: IOrderBridge.TIF.GTC,
            fee: fees
        });
        bridgeOrderData.paymentTokenQuantity = quantityIn - fees;
        assertEq(issuer.getOrderId(bridgeOrderData, salt), orderId);

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        if (quantityIn == 0) {
            vm.expectRevert(DirectBuyIssuer.ZeroValue.selector);
            vm.prank(user);
            issuer.requestOrder(order, salt);
        } else if (fees >= quantityIn) {
            vm.expectRevert(DirectBuyIssuer.OrderTooSmall.selector);
            vm.prank(user);
            issuer.requestOrder(order, salt);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(orderId, user, bridgeOrderData, salt);
            vm.prank(user);
            issuer.requestOrder(order, salt);
            assertTrue(issuer.isOrderActive(orderId));
            assertEq(issuer.getRemainingOrder(orderId), quantityIn - fees);
            assertEq(issuer.numOpenOrders(), 1);
        }
    }

    function testRequestOrderPausedReverts() public {
        issuer.setOrdersPaused(true);

        vm.expectRevert(DirectBuyIssuer.Paused.selector);
        vm.prank(user);
        issuer.requestOrder(dummyOrder, salt);
    }

    function testRequestOrderUnsupportedPaymentReverts(address tryPaymentToken) public {
        vm.assume(!issuer.hasRole(issuer.PAYMENTTOKEN_ROLE(), tryPaymentToken));

        DirectBuyIssuer.BuyOrder memory order = dummyOrder;
        order.paymentToken = tryPaymentToken;

        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(tryPaymentToken),
                    " is missing role ",
                    Strings.toHexString(uint256(issuer.PAYMENTTOKEN_ROLE()), 32)
                )
            )
        );
        vm.prank(user);
        issuer.requestOrder(order, salt);
    }

    function testRequestOrderUnsupportedAssetReverts(address tryAssetToken) public {
        vm.assume(!issuer.hasRole(issuer.ASSETTOKEN_ROLE(), tryAssetToken));

        DirectBuyIssuer.BuyOrder memory order = dummyOrder;
        order.assetToken = tryAssetToken;

        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(tryAssetToken),
                    " is missing role ",
                    Strings.toHexString(uint256(issuer.ASSETTOKEN_ROLE()), 32)
                )
            )
        );
        vm.prank(user);
        issuer.requestOrder(order, salt);
    }

    function testRequestOrderCollisionReverts() public {
        paymentToken.mint(user, 10000);

        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), 10000);

        vm.prank(user);
        issuer.requestOrder(dummyOrder, salt);

        vm.expectRevert(DirectBuyIssuer.DuplicateOrder.selector);
        vm.prank(user);
        issuer.requestOrder(dummyOrder, salt);
    }

    function testRequestOrderWithPermit() public {
        bytes32 orderId = issuer.getOrderIdFromBuyOrder(dummyOrder, salt);
        paymentToken.mint(user, dummyOrder.quantityIn);

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: user,
            spender: address(issuer),
            value: dummyOrder.quantityIn,
            nonce: 0,
            deadline: 30 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        vm.expectEmit(true, true, true, true);
        emit OrderRequested(orderId, user, dummyOrderBridgeData, salt);
        vm.prank(user);
        issuer.requestOrderWithPermit(dummyOrder, salt, permit.value, permit.deadline, v, r, s);
        assertEq(paymentToken.nonces(user), 1);
        assertEq(paymentToken.allowance(user, address(issuer)), 0);
        assertTrue(issuer.isOrderActive(orderId));
        assertEq(issuer.getRemainingOrder(orderId), dummyOrder.quantityIn - dummyOrderFees);
        assertEq(issuer.numOpenOrders(), 1);
    }

    function testTakeOrder(uint128 orderAmount, uint256 takeAmount) public {
        vm.assume(orderAmount > 0);

        DirectBuyIssuer.BuyOrder memory order = dummyOrder;
        order.quantityIn = orderAmount;
        uint256 fees = issuer.getFeesForOrder(order.assetToken, false, order.quantityIn);

        bytes32 orderId = issuer.getOrderIdFromBuyOrder(order, salt);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);
        if (takeAmount == 0) {
            vm.expectRevert(DirectBuyIssuer.ZeroValue.selector);
            vm.prank(operator);
            issuer.takeOrder(order, salt, takeAmount);
        } else if (takeAmount > orderAmount - fees) {
            vm.expectRevert(DirectBuyIssuer.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.takeOrder(order, salt, takeAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderTaken(orderId, user, takeAmount);
            vm.prank(operator);
            issuer.takeOrder(order, salt, takeAmount);
            assertEq(paymentToken.balanceOf(operator), takeAmount);
            assertEq(issuer.getRemainingEscrow(orderId), orderAmount - fees - takeAmount);
        }
    }

    function testFillOrder(uint128 orderAmount, uint128 takeAmount, uint128 fillAmount, uint256 receivedAmount)
        public
    {
        vm.assume(takeAmount > 0);

        DirectBuyIssuer.BuyOrder memory order = dummyOrder;
        order.quantityIn = orderAmount;
        uint256 fees = issuer.getFeesForOrder(order.assetToken, false, order.quantityIn);
        vm.assume(takeAmount <= orderAmount - fees);

        bytes32 orderId = issuer.getOrderIdFromBuyOrder(order, salt);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        vm.prank(operator);
        issuer.takeOrder(order, salt, takeAmount);

        if (fillAmount == 0) {
            vm.expectRevert(DirectBuyIssuer.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount - fees || fillAmount > takeAmount) {
            vm.expectRevert(DirectBuyIssuer.AmountTooLarge.selector);
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

    function testFillorderNoOrderReverts() public {
        vm.expectRevert(DirectBuyIssuer.OrderNotFound.selector);
        vm.prank(operator);
        issuer.fillOrder(dummyOrder, salt, 100, 100);
    }

    function testRequestCancel() public {
        paymentToken.mint(user, dummyOrder.quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), dummyOrder.quantityIn);

        vm.prank(user);
        issuer.requestOrder(dummyOrder, salt);

        bytes32 orderId = issuer.getOrderIdFromBuyOrder(dummyOrder, salt);
        vm.expectEmit(true, true, true, true);
        emit CancelRequested(orderId, user);
        vm.prank(user);
        issuer.requestCancel(dummyOrder, salt);
    }

    function testRequestCancelNotRecipientReverts() public {
        paymentToken.mint(user, dummyOrder.quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), dummyOrder.quantityIn);

        vm.prank(user);
        issuer.requestOrder(dummyOrder, salt);

        vm.expectRevert(DirectBuyIssuer.NotRecipient.selector);
        issuer.requestCancel(dummyOrder, salt);
    }

    function testRequestCancelNotFoundReverts() public {
        vm.expectRevert(DirectBuyIssuer.OrderNotFound.selector);
        vm.prank(user);
        issuer.requestCancel(dummyOrder, salt);
    }

    function testCancelOrder(uint128 orderAmount, uint128 fillAmount, string calldata reason) public {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount > 0);

        DirectBuyIssuer.BuyOrder memory order = dummyOrder;
        order.quantityIn = orderAmount;
        uint256 fees = issuer.getFeesForOrder(order.assetToken, false, order.quantityIn);
        vm.assume(fillAmount < orderAmount - fees);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        vm.prank(operator);
        issuer.takeOrder(order, salt, fillAmount);

        vm.prank(operator);
        issuer.fillOrder(order, salt, fillAmount, 100);

        bytes32 orderId = issuer.getOrderIdFromBuyOrder(order, salt);
        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(orderId, user, reason);
        vm.prank(operator);
        issuer.cancelOrder(order, salt, reason);
    }

    function testCancelOrderNotFoundReverts() public {
        vm.expectRevert(DirectBuyIssuer.OrderNotFound.selector);
        vm.prank(operator);
        issuer.cancelOrder(dummyOrder, salt, "msg");
    }
}
