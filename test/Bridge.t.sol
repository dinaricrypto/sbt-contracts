// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solady/auth/Ownable.sol";
import "solady-test/utils/mocks/MockERC20.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "../src/Bridge.sol";

contract BridgeTest is Test {
    event TreasurySet(address indexed treasury);
    event PaymentTokenEnabled(address indexed token, bool enabled);
    event OrdersPaused(bool paused);
    event PurchaseSubmitted(bytes32 indexed orderId, address indexed user, Bridge.OrderInfo orderInfo);
    event SaleSubmitted(bytes32 indexed orderId, address indexed user, Bridge.OrderInfo orderInfo);
    event PurchaseFulfilled(bytes32 indexed orderId, address indexed user, uint256 amount);
    event SaleFulfilled(bytes32 indexed orderId, address indexed user, uint256 amount);

    BridgedERC20 token;
    Bridge bridge;
    MockERC20 paymentToken;

    address constant user = address(1);
    address constant bridgeOperator = address(3);

    function setUp() public {
        token = new MockBridgedERC20();
        paymentToken = new MockERC20("Money", "$", 18);
        Bridge bridgeImpl = new Bridge();
        bridge =
            Bridge(address(new ERC1967Proxy(address(bridgeImpl), abi.encodeCall(Bridge.initialize, (address(this))))));

        token.grantRoles(address(this), token.minterRole());
        token.grantRoles(address(bridge), token.minterRole());

        bridge.setPaymentTokenEnabled(address(paymentToken), true);
        bridge.grantRoles(bridgeOperator, bridge.operatorRole());
    }

    function testInvariants() public {
        assertEq(bridge.operatorRole(), uint256(1 << 1));
    }

    function testInitialize(address owner) public {
        Bridge bridgeImpl = new Bridge();
        Bridge newBridge =
            Bridge(address(new ERC1967Proxy(address(bridgeImpl), abi.encodeCall(Bridge.initialize, (owner)))));
        assertEq(newBridge.owner(), owner);

        Bridge newImpl = new Bridge();
        vm.expectRevert(Ownable.Unauthorized.selector);
        newBridge.upgradeToAndCall(address(newImpl), abi.encodeCall(Bridge.initialize, (owner)));
    }

    function testSetTreasury(address treasury) public {
        vm.expectEmit(true, true, true, true);
        emit TreasurySet(treasury);
        bridge.setTreasury(treasury);
        assertEq(bridge.treasury(), treasury);
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

    function testSubmitPurchase(uint128 amount, uint128 price) public {
        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            salt: 0x0000000000000000000000000000000000000000000000000000000000000001,
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: amount,
            price: price
        });
        bytes32 orderId = bridge.hashOrderInfo(order);

        uint256 paymentAmount = uint256(amount) * price;
        paymentToken.mint(user, paymentAmount);

        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), paymentAmount);

        if (amount == 0 || price == 0) {
            vm.expectRevert(Bridge.ZeroValue.selector);
            vm.prank(user);
            bridge.submitPurchase(order);
        } else {
            vm.expectEmit(true, true, true, true);
            emit PurchaseSubmitted(orderId, user, order);
            vm.prank(user);
            bridge.submitPurchase(order);
            assertTrue(bridge.isPurchaseActive(orderId));
        }
    }

    function testSubmitPurchasePausedReverts() public {
        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            salt: 0x0000000000000000000000000000000000000000000000000000000000000001,
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: 100,
            price: 100
        });

        bridge.setOrdersPaused(true);

        vm.expectRevert(Bridge.Paused.selector);
        vm.prank(user);
        bridge.submitPurchase(order);
    }

    function testSubmitPurchaseProxyOrderReverts() public {
        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            salt: 0x0000000000000000000000000000000000000000000000000000000000000001,
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: 100,
            price: 100
        });

        vm.expectRevert(Bridge.NoProxyOrders.selector);
        bridge.submitPurchase(order);
    }

    function testSubmitPurchaseUnsupportedPaymentReverts(address tryPaymentToken) public {
        vm.assume(!bridge.paymentTokenEnabled(tryPaymentToken));

        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            salt: 0x0000000000000000000000000000000000000000000000000000000000000001,
            user: user,
            assetToken: address(token),
            paymentToken: tryPaymentToken,
            amount: 100,
            price: 100
        });

        vm.expectRevert(Bridge.UnsupportedPaymentToken.selector);
        vm.prank(user);
        bridge.submitPurchase(order);
    }

    function testSubmitPurchaseCollisionReverts() public {
        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            salt: 0x0000000000000000000000000000000000000000000000000000000000000001,
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: 100,
            price: 100
        });

        paymentToken.mint(user, 10000);

        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), 10000);

        vm.prank(user);
        bridge.submitPurchase(order);

        vm.expectRevert(Bridge.DuplicateOrder.selector);
        vm.prank(user);
        bridge.submitPurchase(order);
    }

    function testSubmitSale(uint128 amount, uint128 price) public {
        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            salt: 0x0000000000000000000000000000000000000000000000000000000000000001,
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: amount,
            price: price
        });
        bytes32 orderId = bridge.hashOrderInfo(order);

        token.mint(user, amount);

        vm.prank(user);
        token.increaseAllowance(address(bridge), amount);

        if (amount == 0 || price == 0) {
            vm.expectRevert(Bridge.ZeroValue.selector);
            vm.prank(user);
            bridge.submitSale(order);
        } else {
            vm.expectEmit(true, true, true, true);
            emit SaleSubmitted(orderId, user, order);
            vm.prank(user);
            bridge.submitSale(order);
            assertTrue(bridge.isSaleActive(orderId));
        }
    }

    function testSubmitSalePausedReverts() public {
        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            salt: 0x0000000000000000000000000000000000000000000000000000000000000001,
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: 100,
            price: 100
        });

        bridge.setOrdersPaused(true);

        vm.expectRevert(Bridge.Paused.selector);
        vm.prank(user);
        bridge.submitSale(order);
    }

    function testSubmitSaleProxyOrderReverts() public {
        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            salt: 0x0000000000000000000000000000000000000000000000000000000000000001,
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: 100,
            price: 100
        });

        vm.expectRevert(Bridge.NoProxyOrders.selector);
        bridge.submitSale(order);
    }

    function testSubmitSaleUnsupportedPaymentReverts(address tryPaymentToken) public {
        vm.assume(!bridge.paymentTokenEnabled(tryPaymentToken));

        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            salt: 0x0000000000000000000000000000000000000000000000000000000000000001,
            user: user,
            assetToken: address(token),
            paymentToken: tryPaymentToken,
            amount: 100,
            price: 100
        });

        vm.expectRevert(Bridge.UnsupportedPaymentToken.selector);
        vm.prank(user);
        bridge.submitSale(order);
    }

    function testSubmitSaleCollisionReverts() public {
        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            salt: 0x0000000000000000000000000000000000000000000000000000000000000001,
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: 100,
            price: 100
        });

        token.mint(user, 100);

        vm.prank(user);
        token.increaseAllowance(address(bridge), 100);

        vm.prank(user);
        bridge.submitSale(order);

        vm.expectRevert(Bridge.DuplicateOrder.selector);
        vm.prank(user);
        bridge.submitSale(order);
    }

    function testFulfillPurchase(uint128 amount, uint128 price, uint128 finalAmount) public {
        vm.assume(amount > 0);
        vm.assume(price > 0);

        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            salt: 0x0000000000000000000000000000000000000000000000000000000000000001,
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: amount,
            price: price
        });
        bytes32 orderId = bridge.hashOrderInfo(order);

        uint256 paymentAmount = uint256(amount) * price;
        paymentToken.mint(user, paymentAmount);

        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), paymentAmount);

        vm.prank(user);
        bridge.submitPurchase(order);

        vm.expectEmit(true, true, true, true);
        emit PurchaseFulfilled(orderId, user, finalAmount);
        vm.prank(bridgeOperator);
        bridge.fulfillPurchase(order, finalAmount);
    }

    function testFulfillPurchaseNoOrderReverts() public {
        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            salt: 0x0000000000000000000000000000000000000000000000000000000000000001,
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: 100,
            price: 100
        });

        vm.expectRevert(Bridge.OrderNotFound.selector);
        vm.prank(bridgeOperator);
        bridge.fulfillPurchase(order, 100);
    }

    function testFulfillSale(uint128 amount, uint128 price, uint128 proceeds) public {
        vm.assume(amount > 0);
        vm.assume(price > 0);
        vm.assume(proceeds > 0);

        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            salt: 0x0000000000000000000000000000000000000000000000000000000000000001,
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: amount,
            price: price
        });
        bytes32 orderId = bridge.hashOrderInfo(order);

        token.mint(user, amount);

        vm.prank(user);
        token.increaseAllowance(address(bridge), amount);

        vm.prank(user);
        bridge.submitSale(order);

        paymentToken.mint(bridgeOperator, proceeds);
        vm.prank(bridgeOperator);
        paymentToken.increaseAllowance(address(bridge), proceeds);

        vm.expectEmit(true, true, true, true);
        emit SaleFulfilled(orderId, user, proceeds);
        vm.prank(bridgeOperator);
        bridge.fulfillSale(order, proceeds);
    }

    function testFulfillSaleNoOrderReverts() public {
        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            salt: 0x0000000000000000000000000000000000000000000000000000000000000001,
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: 100,
            price: 100
        });

        vm.expectRevert(Bridge.OrderNotFound.selector);
        vm.prank(bridgeOperator);
        bridge.fulfillSale(order, 100);
    }
}
