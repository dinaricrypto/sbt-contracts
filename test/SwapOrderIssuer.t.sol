// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solady/auth/Ownable.sol";
import "solady-test/utils/mocks/MockERC20.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "./utils/SigUtils.sol";
import "../src/SwapOrderIssuer.sol";
import {FlatOrderFees} from "../src/FlatOrderFees.sol";

contract SwapOrderIssuerTest is Test {
    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees orderFees);
    event TokenEnabled(address indexed token, bool enabled);
    event OrdersPaused(bool paused);
    event OrderRequested(
        bytes32 indexed id,
        address indexed recipient,
        SwapOrderIssuer.SwapOrder order,
        bytes32 salt,
        uint256 orderAmount
    );
    event OrderFill(bytes32 indexed id, address indexed recipient, uint256 spendAmount);
    event CancelRequested(bytes32 indexed id, address indexed recipient);
    event OrderCancelled(bytes32 indexed id, address indexed recipient, string reason);

    BridgedERC20 token;
    FlatOrderFees orderFees;
    SwapOrderIssuer issuer;
    MockERC20 paymentToken;
    SigUtils sigUtils;

    uint256 userPrivateKey;
    address user;

    address constant operator = address(3);
    address constant treasury = address(4);

    SwapOrderIssuer.SwapOrder dummyOrder;
    bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockBridgedERC20();
        paymentToken = new MockERC20("Money", "$", 18);
        sigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());

        orderFees = new FlatOrderFees();
        orderFees.setFee(0.1 ether);

        SwapOrderIssuer issuerImpl = new SwapOrderIssuer();
        issuer = SwapOrderIssuer(
            address(
                new ERC1967Proxy(address(issuerImpl), abi.encodeCall(SwapOrderIssuer.initialize, (address(this), treasury, orderFees)))
            )
        );

        token.grantRoles(address(this), token.minterRole());
        token.grantRoles(address(issuer), token.minterRole());

        issuer.setTokenEnabled(address(paymentToken), true);
        issuer.setTokenEnabled(address(token), true);
        issuer.grantRoles(operator, issuer.operatorRole());

        dummyOrder = SwapOrderIssuer.SwapOrder({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            quantityIn: 100
        });
    }

    function testInvariants() public {
        assertEq(issuer.operatorRole(), uint256(1 << 1));
    }

    function testInitialize(address owner, address newTreasury) public {
        vm.assume(owner != address(this));

        SwapOrderIssuer issuerImpl = new SwapOrderIssuer();
        if (newTreasury == address(0)) {
            vm.expectRevert(SwapOrderIssuer.ZeroAddress.selector);

            new ERC1967Proxy(address(issuerImpl), abi.encodeCall(SwapOrderIssuer.initialize, (owner, newTreasury, orderFees)));
            return;
        }
        SwapOrderIssuer newIssuer = SwapOrderIssuer(
            address(
                new ERC1967Proxy(address(issuerImpl), abi.encodeCall(SwapOrderIssuer.initialize, (owner, newTreasury, orderFees)))
            )
        );
        assertEq(newIssuer.owner(), owner);

        SwapOrderIssuer newImpl = new SwapOrderIssuer();
        vm.expectRevert(Ownable.Unauthorized.selector);
        newIssuer.upgradeToAndCall(
            address(newImpl), abi.encodeCall(SwapOrderIssuer.initialize, (owner, newTreasury, orderFees))
        );
    }

    function testSetTreasury(address account) public {
        if (account == address(0)) {
            vm.expectRevert(SwapOrderIssuer.ZeroAddress.selector);
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

    function testSetTokenEnabled(address account, bool enabled) public {
        vm.expectEmit(true, true, true, true);
        emit TokenEnabled(account, enabled);
        issuer.setTokenEnabled(account, enabled);
        assertEq(issuer.tokenEnabled(account), enabled);
    }

    function testSetOrdersPaused(bool pause) public {
        vm.expectEmit(true, true, true, true);
        emit OrdersPaused(pause);
        issuer.setOrdersPaused(pause);
        assertEq(issuer.ordersPaused(), pause);
    }

    function testRequestOrder(bool sell, uint128 quantityIn) public {
        SwapOrderIssuer.SwapOrder memory order = SwapOrderIssuer.SwapOrder({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: sell,
            quantityIn: quantityIn
        });
        bytes32 orderId = issuer.getOrderId(order, salt);

        uint256 fees = issuer.getFeesForOrder(order.assetToken, order.sell, order.quantityIn);

        if (sell) {
            token.mint(user, quantityIn);
            vm.prank(user);
            token.increaseAllowance(address(issuer), quantityIn);
        } else {
            paymentToken.mint(user, quantityIn);
            vm.prank(user);
            paymentToken.increaseAllowance(address(issuer), quantityIn);
        }

        if (quantityIn == 0) {
            vm.expectRevert(SwapOrderIssuer.ZeroValue.selector);
            vm.prank(user);
            issuer.requestOrder(order, salt);
        } else if (fees >= quantityIn) {
            vm.expectRevert(SwapOrderIssuer.OrderTooSmall.selector);
            vm.prank(user);
            issuer.requestOrder(order, salt);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(orderId, user, order, salt, quantityIn - fees);
            vm.prank(user);
            issuer.requestOrder(order, salt);
            assertTrue(issuer.isOrderActive(orderId));
            assertEq(issuer.getUnspentAmount(orderId), quantityIn - fees);
            assertEq(issuer.numOpenOrders(), 1);
        }
    }

    function testRequestOrderPausedReverts() public {
        issuer.setOrdersPaused(true);

        vm.expectRevert(SwapOrderIssuer.Paused.selector);
        vm.prank(user);
        issuer.requestOrder(dummyOrder, salt);
    }

    function testRequestOrderUnsupportedPaymentReverts(address tryPaymentToken) public {
        vm.assume(!issuer.tokenEnabled(tryPaymentToken));

        SwapOrderIssuer.SwapOrder memory order = dummyOrder;
        order.paymentToken = tryPaymentToken;

        vm.expectRevert(SwapOrderIssuer.UnsupportedToken.selector);
        vm.prank(user);
        issuer.requestOrder(order, salt);
    }

    function testRequestOrderUnsupportedAssetReverts(address tryAssetToken) public {
        vm.assume(!issuer.tokenEnabled(tryAssetToken));

        SwapOrderIssuer.SwapOrder memory order = dummyOrder;
        order.assetToken = tryAssetToken;

        vm.expectRevert(SwapOrderIssuer.UnsupportedToken.selector);
        vm.prank(user);
        issuer.requestOrder(order, salt);
    }

    function testRequestOrderCollisionReverts() public {
        paymentToken.mint(user, 10000);

        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), 10000);

        vm.prank(user);
        issuer.requestOrder(dummyOrder, salt);

        vm.expectRevert(SwapOrderIssuer.DuplicateOrder.selector);
        vm.prank(user);
        issuer.requestOrder(dummyOrder, salt);
    }

    function testRequestOrderWithPermit() public {
        bytes32 orderId = issuer.getOrderId(dummyOrder, salt);
        uint256 fees = issuer.getFeesForOrder(dummyOrder.assetToken, dummyOrder.sell, dummyOrder.quantityIn);
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
        emit OrderRequested(orderId, user, dummyOrder, salt, dummyOrder.quantityIn - fees);
        vm.prank(user);
        issuer.requestOrderWithPermit(dummyOrder, salt, permit.value, permit.deadline, v, r, s);
        assertEq(paymentToken.nonces(user), 1);
        assertEq(paymentToken.allowance(user, address(issuer)), 0);
        assertTrue(issuer.isOrderActive(orderId));
        assertEq(issuer.getUnspentAmount(orderId), dummyOrder.quantityIn - fees);
        assertEq(issuer.numOpenOrders(), 1);
    }

    function testFillOrder(bool sell, uint128 orderAmount, uint128 fillAmount) public {
        vm.assume(orderAmount > 0);

        SwapOrderIssuer.SwapOrder memory order = dummyOrder;
        order.sell = sell;
        order.quantityIn = orderAmount;
        uint256 fees = issuer.getFeesForOrder(order.assetToken, order.sell, order.quantityIn);

        bytes32 orderId = issuer.getOrderId(order, salt);

        if (sell) {
            token.mint(user, orderAmount);
            vm.prank(user);
            token.increaseAllowance(address(issuer), orderAmount);

            paymentToken.mint(operator, fillAmount);
            vm.prank(operator);
            paymentToken.increaseAllowance(address(issuer), fillAmount);
        } else {
            paymentToken.mint(user, orderAmount);
            vm.prank(user);
            paymentToken.increaseAllowance(address(issuer), orderAmount);
        }

        vm.prank(user);
        issuer.requestOrder(order, salt);

        if (fillAmount == 0) {
            vm.expectRevert(SwapOrderIssuer.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, 0);
        } else if (fillAmount > orderAmount - fees) {
            vm.expectRevert(SwapOrderIssuer.FillTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, 0);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderFill(orderId, user, fillAmount);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, 0);
            assertEq(issuer.getUnspentAmount(orderId), orderAmount - fees - fillAmount);
            if (fillAmount == orderAmount) {
                assertEq(issuer.numOpenOrders(), 0);
            }
        }
    }

    function testFillorderNoOrderReverts() public {
        vm.expectRevert(SwapOrderIssuer.OrderNotFound.selector);
        vm.prank(operator);
        issuer.fillOrder(dummyOrder, salt, 100, 100);
    }

    function testRequestCancel() public {
        paymentToken.mint(user, dummyOrder.quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), dummyOrder.quantityIn);

        vm.prank(user);
        issuer.requestOrder(dummyOrder, salt);

        bytes32 orderId = issuer.getOrderId(dummyOrder, salt);
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

        vm.expectRevert(SwapOrderIssuer.NotRecipient.selector);
        issuer.requestCancel(dummyOrder, salt);
    }

    function testRequestCancelNotFoundReverts() public {
        vm.expectRevert(SwapOrderIssuer.OrderNotFound.selector);
        vm.prank(user);
        issuer.requestCancel(dummyOrder, salt);
    }

    function testCancelOrder(uint128 orderAmount, uint128 fillAmount, string calldata reason) public {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount > 0);

        SwapOrderIssuer.SwapOrder memory order = dummyOrder;
        order.quantityIn = orderAmount;
        uint256 fees = issuer.getFeesForOrder(order.assetToken, order.sell, order.quantityIn);
        vm.assume(fillAmount < orderAmount - fees);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        vm.prank(operator);
        issuer.fillOrder(order, salt, fillAmount, 100);

        bytes32 orderId = issuer.getOrderId(order, salt);
        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(orderId, user, reason);
        vm.prank(operator);
        issuer.cancelOrder(order, salt, reason);
    }

    function testCancelOrderNotFoundReverts() public {
        vm.expectRevert(SwapOrderIssuer.OrderNotFound.selector);
        vm.prank(operator);
        issuer.cancelOrder(dummyOrder, salt, "msg");
    }
}
