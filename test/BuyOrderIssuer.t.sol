// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import "./utils/mocks/MockdShare.sol";
import "./utils/SigUtils.sol";
import "../src/issuer/BuyOrderIssuer.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import {NumberUtils} from "./utils/NumberUtils.sol";

contract BuyOrderIssuerTest is Test {
    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees indexed orderFees);
    event OrdersPaused(bool paused);

    event OrderRequested(bytes32 indexed id, address indexed recipient, IOrderBridge.Order order, bytes32 salt);
    event OrderFill(bytes32 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount);
    event OrderFulfilled(bytes32 indexed id, address indexed recipient);
    event CancelRequested(bytes32 indexed id, address indexed recipient);
    event OrderCancelled(bytes32 indexed id, address indexed recipient, string reason);

    dShare token;
    OrderFees orderFees;
    BuyOrderIssuer issuer;
    MockERC20 paymentToken;
    SigUtils sigUtils;

    uint256 userPrivateKey;
    address user;

    address constant operator = address(3);
    address constant treasury = address(4);

    bytes32 constant salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
    uint256 dummyOrderFees;
    IOrderBridge.Order dummyOrderBridgeData;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockdShare();
        paymentToken = new MockERC20("Money", "$", 6);
        sigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());

        orderFees = new OrderFees(address(this), 1 ether, 500_000);
        orderFees = new OrderFees(address(this), 1 ether, 500_000);

        issuer = new BuyOrderIssuer(address(this), treasury, orderFees);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);

        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(address(paymentToken), 100 ether);
        dummyOrderFees = flatFee + percentageFee;
        dummyOrderBridgeData = IOrderBridge.Order({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderBridge.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 100 ether,
            price: 0,
            tif: IOrderBridge.TIF.GTC,
            fee: dummyOrderFees
        });
    }

    function testSetTreasury(address account) public {
        vm.assume(account != address(0));

        vm.expectEmit(true, true, true, true);
        emit TreasurySet(account);
        issuer.setTreasury(account);
        assertEq(issuer.treasury(), account);
    }

    function testSetTreasuryZeroReverts() public {
        vm.expectRevert(OrderProcessor.ZeroAddress.selector);
        issuer.setTreasury(address(0));
    }

    function testSetFees(IOrderFees fees) public {
        vm.expectEmit(true, true, true, true);
        emit OrderFeesSet(fees);
        issuer.setOrderFees(fees);
        assertEq(address(issuer.orderFees()), address(fees));
    }

    function testNoFees(uint256 value) public {
        issuer.setOrderFees(IOrderFees(address(0)));

        (uint256 inputValue, uint256 flatFee, uint256 percentageFee) =
            issuer.getInputValueForOrderValue(address(paymentToken), value);
        assertEq(inputValue, value);
        assertEq(flatFee, 0);
        assertEq(percentageFee, 0);
        (uint256 flatFee2, uint256 percentageFee2) = issuer.getFeesForOrder(address(paymentToken), value);
        assertEq(flatFee2, 0);
        assertEq(percentageFee2, 0);
    }

    function testGetInputValue(uint24 perOrderFee, uint24 percentageFeeRate, uint128 orderValue) public {
        // uint128 used to avoid overflow when calculating larger raw input value
        vm.assume(percentageFeeRate < 1_000_000);
        vm.assume(percentageFeeRate < 1_000_000);
        OrderFees fees = new OrderFees(address(this), perOrderFee, percentageFeeRate);
        issuer.setOrderFees(fees);
        (uint256 inputValue, uint256 flatFee, uint256 percentageFee) =
            issuer.getInputValueForOrderValue(address(paymentToken), orderValue);
        assertEq(inputValue - flatFee - percentageFee, orderValue);
        (uint256 flatFee2, uint256 percentageFee2) = issuer.getFeesForOrder(address(paymentToken), inputValue);
        assertEq(flatFee, flatFee2);
        assertEq(percentageFee, percentageFee2);
    }

    function testSetOrdersPaused(bool pause) public {
        vm.expectEmit(true, true, true, true);
        emit OrdersPaused(pause);
        issuer.setOrdersPaused(pause);
        assertEq(issuer.ordersPaused(), pause);
    }

    function testRequestOrder(uint256 orderAmount) public {
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(address(paymentToken), orderAmount);
        uint256 fees = flatFee + percentageFee;
        IOrderBridge.Order memory order = IOrderBridge.Order({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderBridge.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: orderAmount,
            price: 0,
            tif: IOrderBridge.TIF.GTC,
            fee: fees
        });
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        bytes32 orderId = issuer.getOrderId(order, salt);

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        if (orderAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(user);
            issuer.requestOrder(order, salt);
        } else {
            // balances before
            uint256 userBalanceBefore = paymentToken.balanceOf(user);
            uint256 issuerBalanceBefore = paymentToken.balanceOf(address(issuer));
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(orderId, user, order, salt);
            vm.prank(user);
            issuer.requestOrder(order, salt);
            assertTrue(issuer.isOrderActive(orderId));
            assertEq(issuer.getRemainingOrder(orderId), quantityIn - fees);
            assertEq(issuer.numOpenOrders(), 1);
            assertEq(issuer.getOrderId(order, salt), orderId);
            // balances after
            assertEq(paymentToken.balanceOf(address(user)), userBalanceBefore - quantityIn);
            assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + quantityIn);
            assertEq(issuer.escrowedBalanceTotal(order.paymentToken, user), orderAmount);
        }
    }

    function testRequestOrderPausedReverts() public {
        issuer.setOrdersPaused(true);

        vm.expectRevert(OrderProcessor.Paused.selector);
        vm.prank(user);
        issuer.requestOrder(dummyOrderBridgeData, salt);
    }

    function testRequestOrderUnsupportedPaymentReverts(address tryPaymentToken) public {
        vm.assume(!issuer.hasRole(issuer.PAYMENTTOKEN_ROLE(), tryPaymentToken));

        IOrderBridge.Order memory order = dummyOrderBridgeData;
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

        IOrderBridge.Order memory order = dummyOrderBridgeData;
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
        paymentToken.mint(user, dummyOrderBridgeData.paymentTokenQuantity + dummyOrderFees);

        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), dummyOrderBridgeData.paymentTokenQuantity + dummyOrderFees);

        vm.prank(user);
        issuer.requestOrder(dummyOrderBridgeData, salt);

        vm.expectRevert(OrderProcessor.DuplicateOrder.selector);
        vm.prank(user);
        issuer.requestOrder(dummyOrderBridgeData, salt);
    }

    function testRequestOrderWithPermit() public {
        bytes32 orderId = issuer.getOrderId(dummyOrderBridgeData, salt);
        uint256 quantityIn = dummyOrderBridgeData.paymentTokenQuantity + dummyOrderFees;
        paymentToken.mint(user, quantityIn);

        SigUtils.Permit memory permit =
            SigUtils.Permit({owner: user, spender: address(issuer), value: quantityIn, nonce: 0, deadline: 30 days});

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            issuer.selfPermit.selector, address(paymentToken), permit.value, permit.deadline, v, r, s
        );
        calls[1] = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrderBridgeData, salt);

        // balances before
        uint256 userBalanceBefore = paymentToken.balanceOf(user);
        uint256 issuerBalanceBefore = paymentToken.balanceOf(address(issuer));
        vm.expectEmit(true, true, true, true);
        emit OrderRequested(orderId, user, dummyOrderBridgeData, salt);
        vm.prank(user);
        issuer.multicall(calls);
        assertEq(paymentToken.nonces(user), 1);
        assertEq(paymentToken.allowance(user, address(issuer)), 0);
        assertTrue(issuer.isOrderActive(orderId));
        assertEq(issuer.getRemainingOrder(orderId), dummyOrderBridgeData.paymentTokenQuantity);
        assertEq(issuer.numOpenOrders(), 1);
        // balances after
        assertEq(paymentToken.balanceOf(address(user)), userBalanceBefore - quantityIn);
        assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + quantityIn);
    }

    function testFillOrder(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount) public {
        vm.assume(orderAmount > 0);

        IOrderBridge.Order memory order = dummyOrderBridgeData;
        order.paymentTokenQuantity = orderAmount;
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.paymentToken, orderAmount);
        uint256 fees = flatFee + percentageFee;
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        bytes32 orderId = issuer.getOrderId(order, salt);

        {
            paymentToken.mint(user, quantityIn);
            vm.prank(user);
            paymentToken.increaseAllowance(address(issuer), quantityIn);

            vm.prank(user);
            issuer.requestOrder(order, salt);
            uint256 escrowedAmount = issuer.escrowedBalanceTotal(order.paymentToken, user);
            assertEq(escrowedAmount, orderAmount);
        }

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
        } else {
            // balances before
            uint256 userAssetBefore = token.balanceOf(user);
            uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
            uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
            vm.expectEmit(true, true, true, true);
            emit OrderFill(orderId, user, fillAmount, receivedAmount);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
            assertEq(issuer.getRemainingOrder(orderId), orderAmount - fillAmount);
            if (fillAmount == orderAmount) {
                assertEq(issuer.numOpenOrders(), 0);
                assertEq(issuer.getTotalReceived(orderId), 0);
            } else {
                assertEq(issuer.getTotalReceived(orderId), receivedAmount);
                // balances after
                assertEq(token.balanceOf(address(user)), userAssetBefore + receivedAmount);
                assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore - fillAmount);
                assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore + fillAmount);
                assertEq(issuer.escrowedBalanceTotal(order.paymentToken, user), orderAmount - fillAmount);
            }
        }
    }

    function testFulfillOrder(uint256 orderAmount, uint256 receivedAmount) public {
        vm.assume(orderAmount > 0);

        IOrderBridge.Order memory order = dummyOrderBridgeData;
        order.paymentTokenQuantity = orderAmount;
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.paymentToken, orderAmount);
        uint256 fees = flatFee + percentageFee;
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        bytes32 orderId = issuer.getOrderId(order, salt);

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        // balances before
        uint256 userAssetBefore = token.balanceOf(user);
        uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
        uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
        uint256 treasuryPaymentBefore = paymentToken.balanceOf(treasury);
        vm.expectEmit(true, true, true, true);
        emit OrderFulfilled(orderId, user);
        vm.prank(operator);
        issuer.fillOrder(order, salt, orderAmount, receivedAmount);
        assertEq(issuer.getRemainingOrder(orderId), 0);
        assertEq(issuer.numOpenOrders(), 0);
        assertEq(issuer.getTotalReceived(orderId), 0);
        // balances after
        assertEq(token.balanceOf(address(user)), userAssetBefore + receivedAmount);
        assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore - quantityIn);
        assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore + orderAmount);
        assertEq(paymentToken.balanceOf(treasury), treasuryPaymentBefore + fees);
    }

    function testFillorderNoOrderReverts() public {
        vm.expectRevert(OrderProcessor.OrderNotFound.selector);
        vm.prank(operator);
        issuer.fillOrder(dummyOrderBridgeData, salt, 100, 100);
    }

    function testRequestCancel() public {
        paymentToken.mint(user, dummyOrderBridgeData.paymentTokenQuantity + dummyOrderFees);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), dummyOrderBridgeData.paymentTokenQuantity + dummyOrderFees);

        vm.prank(user);
        issuer.requestOrder(dummyOrderBridgeData, salt);

        bytes32 orderId = issuer.getOrderId(dummyOrderBridgeData, salt);
        vm.expectEmit(true, true, true, true);
        emit CancelRequested(orderId, user);
        vm.prank(user);
        issuer.requestCancel(dummyOrderBridgeData, salt);
    }

    function testRequestCancelNotRequesterReverts() public {
        paymentToken.mint(user, dummyOrderBridgeData.paymentTokenQuantity + dummyOrderFees);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), dummyOrderBridgeData.paymentTokenQuantity + dummyOrderFees);

        vm.prank(user);
        issuer.requestOrder(dummyOrderBridgeData, salt);

        vm.expectRevert(OrderProcessor.NotRequester.selector);
        issuer.requestCancel(dummyOrderBridgeData, salt);
    }

    function testRequestCancelNotFoundReverts() public {
        vm.expectRevert(OrderProcessor.OrderNotFound.selector);
        vm.prank(user);
        issuer.requestCancel(dummyOrderBridgeData, salt);
    }

    function testCancelOrder(uint256 orderAmount, uint256 fillAmount, string calldata reason) public {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount < orderAmount);

        IOrderBridge.Order memory order = dummyOrderBridgeData;
        order.paymentTokenQuantity = orderAmount;
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.paymentToken, orderAmount);
        uint256 fees = flatFee + percentageFee;
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        {
            paymentToken.mint(user, quantityIn);
            vm.prank(user);
            paymentToken.increaseAllowance(address(issuer), quantityIn);

            vm.prank(user);
            issuer.requestOrder(order, salt);
            uint256 escrowedAmount = issuer.escrowedBalanceTotal(order.paymentToken, user);
            assertEq(escrowedAmount, orderAmount);
        }

        if (fillAmount > 0) {
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, 100);
        }

        bytes32 orderId = issuer.getOrderId(order, salt);

        // balances before
        uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(orderId, user, reason);
        vm.prank(operator);
        issuer.cancelOrder(order, salt, reason);
        // balances after
        assertEq(issuer.escrowedBalanceTotal(order.paymentToken, user), 0);
        if (fillAmount > 0) {
            // uint256 feesEarned = percentageFee * fillAmount / (orderAmount - fees) + flatFee;
            uint256 feesEarned = PrbMath.mulDiv(percentageFee, fillAmount, orderAmount) + flatFee;
            uint256 escrow = quantityIn - fillAmount;
            assertEq(paymentToken.balanceOf(address(user)), escrow - feesEarned);
            assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore - escrow);
            assertEq(paymentToken.balanceOf(treasury), feesEarned);
        } else {
            assertEq(paymentToken.balanceOf(address(user)), quantityIn);
            assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore - quantityIn);
        }
    }

    function testCancelOrderNotFoundReverts() public {
        vm.expectRevert(OrderProcessor.OrderNotFound.selector);
        vm.prank(operator);
        issuer.cancelOrder(dummyOrderBridgeData, salt, "msg");
    }
}
