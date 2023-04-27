// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "solady-test/utils/mocks/MockERC20.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "../src/Bridge.sol";

contract BridgeTest is Test {
    event PaymentTokenEnabled(address indexed token, bool enabled);
    event PurchaseSubmitted(bytes32 indexed orderId, address indexed user, Bridge.OrderInfo orderInfo);
    event RedemptionSubmitted(bytes32 indexed orderId, address indexed user, Bridge.OrderInfo orderInfo);
    event PurchaseFulfilled(bytes32 indexed orderId, address indexed user, uint256 amount);
    event RedemptionFulfilled(bytes32 indexed orderId, address indexed user, uint256 amount);

    BridgedERC20 token;
    Bridge bridge;
    MockERC20 paymentToken;

    address constant user = address(1);
    address constant bridgeOperator = address(3);
    uint256 constant alot = 340282366920938463463374607431768211455; // sqrt(type(uint256).max)

    function setUp() public {
        token = new MockBridgedERC20();
        bridge = new Bridge();
        paymentToken = new MockERC20("Money", "$", 18);

        token.grantRoles(address(this), token.minterRole());
        token.grantRoles(address(bridge), token.minterRole());

        bridge.setPaymentTokenEnabled(address(paymentToken), true);
        bridge.grantRoles(bridgeOperator, bridge.operatorRole());
    }

    function testInvariants() public {
        assertEq(bridge.operatorRole(), uint256(1 << 1));
    }

    function testSetPaymentTokenEnabled(address account, bool enabled) public {
        vm.expectEmit(true, true, true, true);
        emit PaymentTokenEnabled(account, enabled);
        bridge.setPaymentTokenEnabled(account, enabled);
        assertEq(bridge.paymentTokenEnabled(account), enabled);
    }

    function testSubmitPurchase(uint256 amount, uint224 price, uint32 expirationBlock, uint64 maxSlippage) public {
        vm.assume(amount < alot);
        vm.assume(price < alot);

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

        uint256 paymentAmount = amount * price;
        paymentToken.mint(user, paymentAmount);

        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), paymentAmount);

        if (amount == 0 || price == 0) {
            vm.expectRevert(Bridge.ZeroValue.selector);
            vm.prank(user);
            bridge.submitPurchase(order);
        } else if (maxSlippage > 1 ether) {
            vm.expectRevert(Bridge.SlippageLimitTooLarge.selector);
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

    function testSubmitRedemption(uint256 amount, uint224 price, uint32 expirationBlock, uint64 maxSlippage) public {
        vm.assume(amount < alot);
        vm.assume(price < alot);

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

        token.mint(user, amount);

        vm.prank(user);
        token.increaseAllowance(address(bridge), amount);

        if (amount == 0 || price == 0) {
            vm.expectRevert(Bridge.ZeroValue.selector);
            vm.prank(user);
            bridge.submitRedemption(order);
        } else if (maxSlippage > 1 ether) {
            vm.expectRevert(Bridge.SlippageLimitTooLarge.selector);
            vm.prank(user);
            bridge.submitRedemption(order);
        } else {
            vm.expectEmit(true, true, true, true);
            emit RedemptionSubmitted(orderId, user, order);
            vm.prank(user);
            bridge.submitRedemption(order);
            assertTrue(bridge.isRedemptionActive(orderId));
        }
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

    function testFulfillPurchase(
        uint256 amount,
        uint224 price,
        uint32 expirationBlock,
        uint64 maxSlippage,
        uint256 finalAmount
    ) public {
        vm.assume(amount < alot);
        vm.assume(price < alot);
        vm.assume(amount > 0);
        vm.assume(price > 0);
        vm.assume(maxSlippage < 1 ether);
        vm.assume(finalAmount < alot);

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

        uint256 paymentAmount = amount * price;
        paymentToken.mint(user, paymentAmount);

        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), paymentAmount);

        vm.prank(user);
        bridge.submitPurchase(order);

        if (finalAmount > amount * (1 ether + maxSlippage) / 1 ether) {
            vm.expectRevert(Bridge.SlippageLimitExceeded.selector);
            vm.prank(bridgeOperator);
            bridge.fulfillPurchase(order, finalAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit PurchaseFulfilled(orderId, user, finalAmount);
            vm.prank(bridgeOperator);
            bridge.fulfillPurchase(order, finalAmount);
        }
    }

    function testFulfillPurchaseNoOrderReverts() public {
        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: 100,
            price: 100,
            expirationBlock: uint32(block.number),
            maxSlippage: 0
        });

        vm.expectRevert(Bridge.OrderNotFound.selector);
        vm.prank(bridgeOperator);
        bridge.fulfillPurchase(order, 100);
    }

    function testFulfillRedemption(
        uint256 amount,
        uint224 price,
        uint32 expirationBlock,
        uint64 maxSlippage,
        uint256 proceeds
    ) public {
        vm.assume(amount < alot);
        vm.assume(price < alot);
        vm.assume(amount > 0);
        vm.assume(price > 0);
        vm.assume(maxSlippage < 1 ether);
        vm.assume(proceeds < alot);
        vm.assume(proceeds > 0);

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

        token.mint(user, amount);

        vm.prank(user);
        token.increaseAllowance(address(bridge), amount);

        vm.prank(user);
        bridge.submitRedemption(order);

        paymentToken.mint(bridgeOperator, proceeds);
        vm.prank(bridgeOperator);
        paymentToken.increaseAllowance(address(bridge), proceeds);

        if (proceeds / amount < price * (1 ether - maxSlippage) / 1 ether) {
            vm.expectRevert(Bridge.SlippageLimitExceeded.selector);
            vm.prank(bridgeOperator);
            bridge.fulfillRedemption(order, proceeds);
        } else {
            vm.expectEmit(true, true, true, true);
            emit RedemptionFulfilled(orderId, user, proceeds);
            vm.prank(bridgeOperator);
            bridge.fulfillRedemption(order, proceeds);
        }
    }

    function testFulfillRedemptionNoOrderReverts() public {
        Bridge.OrderInfo memory order = Bridge.OrderInfo({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            amount: 100,
            price: 100,
            expirationBlock: uint32(block.number),
            maxSlippage: 0
        });

        vm.expectRevert(Bridge.OrderNotFound.selector);
        vm.prank(bridgeOperator);
        bridge.fulfillRedemption(order, 100);
    }
}
