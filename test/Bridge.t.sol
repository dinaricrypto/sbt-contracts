// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solady-test/utils/mocks/MockERC20.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "../src/Bridge.sol";

contract BridgeTest is Test {
    event PaymentTokenEnabled(address indexed token, bool enabled);
    event PurchaseSubmitted(bytes32 indexed orderId, address indexed user, Bridge.OrderInfo orderInfo);
    event RedemptionSubmitted(bytes32 indexed orderId, address indexed user, Bridge.OrderInfo orderInfo);

    BridgedERC20 token;
    Bridge bridge;
    MockERC20 paymentToken;

    address constant user = address(1);

    function setUp() public {
        token = new MockBridgedERC20();
        bridge = new Bridge();
        paymentToken = new MockERC20("Money", "$", 18);

        token.grantRoles(address(this), token.minterRole());

        bridge.setPaymentTokenEnabled(address(paymentToken), true);

        paymentToken.mint(user, type(uint256).max);
        token.mint(user, type(uint256).max);
    }

    function testSetPaymentTokenEnabled(address account, bool enabled) public {
        vm.expectEmit(true, true, true, true);
        emit PaymentTokenEnabled(account, enabled);
        bridge.setPaymentTokenEnabled(account, enabled);
        assertEq(bridge.paymentTokenEnabled(account), enabled);
    }

    function testSubmitPurchase(uint256 amount, uint224 price, uint32 expirationBlock, uint256 maxSlippage) public {
        vm.assume(amount < 340282366920938463463374607431768211456); // sqrt(type(uint256).max)
        vm.assume(price < 340282366920938463463374607431768211456); // sqrt(type(uint256).max)

        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: amount,
            price: price,
            expirationBlock: expirationBlock,
            maxSlippage: maxSlippage
        });
        bytes32 orderId = bridge.hashOrderInfo(order);

        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), amount * price);

        vm.expectEmit(true, true, true, true);
        emit PurchaseSubmitted(orderId, user, order);
        vm.prank(user);
        bridge.submitPurchase(order);
        assertTrue(bridge.isPurchaseActive(orderId));
    }

    function testSubmitPurchaseProxyOrderReverts() public {
        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: 100,
            price: 100,
            expirationBlock: uint32(block.number),
            maxSlippage: 0
        });

        vm.expectRevert(Bridge.NoProxyOrders.selector);
        bridge.submitPurchase(order);
    }

    function testSubmitPurchaseUnsupportedPaymentReverts(address tryPaymentToken) public {
        vm.assume(!bridge.paymentTokenEnabled(tryPaymentToken));

        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            user: user,
            assetToken: address(token),
            paymentToken: tryPaymentToken,
            amount: 100,
            price: 100,
            expirationBlock: uint32(block.number),
            maxSlippage: 0
        });

        vm.expectRevert(Bridge.UnsupportedPaymentToken.selector);
        vm.prank(user);
        bridge.submitPurchase(order);
    }

    function testSubmitRedemption(uint256 amount, uint224 price, uint32 expirationBlock, uint256 maxSlippage) public {
        vm.assume(amount < 340282366920938463463374607431768211456); // sqrt(type(uint256).max)
        vm.assume(price < 340282366920938463463374607431768211456); // sqrt(type(uint256).max)

        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: amount,
            price: price,
            expirationBlock: expirationBlock,
            maxSlippage: maxSlippage
        });
        bytes32 orderId = bridge.hashOrderInfo(order);

        vm.prank(user);
        token.increaseAllowance(address(bridge), amount);

        vm.expectEmit(true, true, true, true);
        emit RedemptionSubmitted(orderId, user, order);
        vm.prank(user);
        bridge.submitRedemption(order);
        assertTrue(bridge.isRedemptionActive(orderId));
    }

    function testSubmitRedemptionProxyOrderReverts() public {
        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: 100,
            price: 100,
            expirationBlock: uint32(block.number),
            maxSlippage: 0
        });

        vm.expectRevert(Bridge.NoProxyOrders.selector);
        bridge.submitRedemption(order);
    }

    function testSubmitRedemptionUnsupportedPaymentReverts(address tryPaymentToken) public {
        vm.assume(!bridge.paymentTokenEnabled(tryPaymentToken));

        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            user: user,
            assetToken: address(token),
            paymentToken: tryPaymentToken,
            amount: 100,
            price: 100,
            expirationBlock: uint32(block.number),
            maxSlippage: 0
        });

        vm.expectRevert(Bridge.UnsupportedPaymentToken.selector);
        vm.prank(user);
        bridge.submitRedemption(order);
    }
}
