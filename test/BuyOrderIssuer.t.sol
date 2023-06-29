// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "./utils/SigUtils.sol";
import "../src/issuer/BuyOrderIssuer.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract BuyOrderIssuerTest is Test {
    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees indexed orderFees);
    event OrdersPaused(bool paused);

    event OrderRequested(bytes32 indexed id, address indexed recipient, IOrderBridge.Order order, bytes32 salt);
    event OrderFill(bytes32 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount);
    event OrderFulfilled(bytes32 indexed id, address indexed recipient);
    event CancelRequested(bytes32 indexed id, address indexed recipient);
    event OrderCancelled(bytes32 indexed id, address indexed recipient, string reason);

    BridgedERC20 token;
    OrderFees orderFees;
    BuyOrderIssuer issuer;
    MockERC20 paymentToken;
    SigUtils sigUtils;

    uint256 userPrivateKey;
    address user;

    address constant operator = address(3);
    address constant treasury = address(4);

    bytes32 constant salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
    OrderProcessor.OrderRequest dummyOrder;
    uint256 dummyOrderFees;
    IOrderBridge.Order dummyOrderBridgeData;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockBridgedERC20();
        paymentToken = new MockERC20("Money", "$", 6);
        sigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());

        orderFees = new OrderFees(address(this), 1 ether, 0.005 ether);

        BuyOrderIssuer issuerImpl = new BuyOrderIssuer();
        issuer = BuyOrderIssuer(
            address(
                new ERC1967Proxy(address(issuerImpl), abi.encodeCall(issuerImpl.initialize, (address(this), treasury, orderFees)))
            )
        );

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);

        dummyOrder = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: 100 ether,
            price: 0
        });
        (uint256 flatFee, uint256 percentageFee) =
            issuer.getFeesForOrder(dummyOrder.paymentToken, dummyOrder.quantityIn);
        dummyOrderFees = flatFee + percentageFee;
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
        vm.assume(owner != address(this) && owner != address(0));
        vm.assume(newTreasury != address(0));

        BuyOrderIssuer issuerImpl = new BuyOrderIssuer();
        BuyOrderIssuer newIssuer = BuyOrderIssuer(
            address(
                new ERC1967Proxy(address(issuerImpl), abi.encodeCall(issuerImpl.initialize, (owner, newTreasury, orderFees)))
            )
        );
        assertEq(newIssuer.owner(), owner);

        // revert if already initialized
        BuyOrderIssuer newImpl = new BuyOrderIssuer();
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

    function testInitializeZeroOwnerReverts() public {
        BuyOrderIssuer issuerImpl = new BuyOrderIssuer();
        vm.expectRevert("AccessControl: 0 default admin");
        new ERC1967Proxy(address(issuerImpl), abi.encodeCall(issuerImpl.initialize, (address(0), treasury, orderFees)));
    }

    function testInitializeZeroTreasuryReverts() public {
        BuyOrderIssuer issuerImpl = new BuyOrderIssuer();
        vm.expectRevert(OrderProcessor.ZeroAddress.selector);
        new ERC1967Proxy(address(issuerImpl), abi.encodeCall(issuerImpl.initialize, (address(this), address(0), orderFees)));
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

    function testGetInputValue(uint64 perOrderFee, uint64 percentageFeeRate, uint128 orderValue) public {
        // uint128 used to avoid overflow when calculating larger raw input value
        vm.assume(percentageFeeRate < 1 ether);
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

    function testRequestOrder(uint256 quantityIn) public {
        OrderProcessor.OrderRequest memory order = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: quantityIn,
            price: 0
        });
        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);

        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.paymentToken, order.quantityIn);
        uint256 fees = flatFee + percentageFee;
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
        bridgeOrderData.paymentTokenQuantity = 0;
        if (quantityIn > fees) {
            bridgeOrderData.paymentTokenQuantity = quantityIn - fees;
        }

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        if (quantityIn == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(user);
            issuer.requestOrder(order, salt);
        } else if (fees >= quantityIn) {
            vm.expectRevert(BuyOrderIssuer.OrderTooSmall.selector);
            vm.prank(user);
            issuer.requestOrder(order, salt);
        } else {
            // balances before
            uint256 userBalanceBefore = paymentToken.balanceOf(user);
            uint256 issuerBalanceBefore = paymentToken.balanceOf(address(issuer));
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(orderId, user, bridgeOrderData, salt);
            vm.prank(user);
            issuer.requestOrder(order, salt);
            assertTrue(issuer.isOrderActive(orderId));
            assertEq(issuer.getRemainingOrder(orderId), quantityIn - fees);
            assertEq(issuer.numOpenOrders(), 1);
            assertEq(issuer.getOrderId(bridgeOrderData, salt), orderId);
            // balances after
            assertEq(paymentToken.balanceOf(address(user)), userBalanceBefore - quantityIn);
            assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + quantityIn);
        }
    }

    function testRequestOrderPausedReverts() public {
        issuer.setOrdersPaused(true);

        vm.expectRevert(OrderProcessor.Paused.selector);
        vm.prank(user);
        issuer.requestOrder(dummyOrder, salt);
    }

    function testRequestOrderUnsupportedPaymentReverts(address tryPaymentToken) public {
        vm.assume(!issuer.hasRole(issuer.PAYMENTTOKEN_ROLE(), tryPaymentToken));

        OrderProcessor.OrderRequest memory order = dummyOrder;
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

        OrderProcessor.OrderRequest memory order = dummyOrder;
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
        paymentToken.mint(user, dummyOrder.quantityIn);

        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), dummyOrder.quantityIn);

        vm.prank(user);
        issuer.requestOrder(dummyOrder, salt);

        vm.expectRevert(OrderProcessor.DuplicateOrder.selector);
        vm.prank(user);
        issuer.requestOrder(dummyOrder, salt);
    }

    function testRequestOrderWithPermit() public {
        bytes32 orderId = issuer.getOrderIdFromOrderRequest(dummyOrder, salt);
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

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            issuer.selfPermit.selector, address(paymentToken), permit.value, permit.deadline, v, r, s
        );
        calls[1] = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder, salt);

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
        assertEq(issuer.getRemainingOrder(orderId), dummyOrder.quantityIn - dummyOrderFees);
        assertEq(issuer.numOpenOrders(), 1);
        // balances after
        assertEq(paymentToken.balanceOf(address(user)), userBalanceBefore - dummyOrder.quantityIn);
        assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + dummyOrder.quantityIn);
    }

    function testFillOrder(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount) public {
        OrderProcessor.OrderRequest memory order = dummyOrder;
        order.quantityIn = orderAmount;
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.paymentToken, order.quantityIn);
        uint256 fees = flatFee + percentageFee;
        vm.assume(fees < orderAmount);

        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount - fees) {
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
            assertEq(issuer.getRemainingOrder(orderId), orderAmount - fees - fillAmount);
            if (fillAmount == orderAmount - fees) {
                assertEq(issuer.numOpenOrders(), 0);
                assertEq(issuer.getTotalReceived(orderId), 0);
            } else {
                assertEq(issuer.getTotalReceived(orderId), receivedAmount);
                // balances after
                assertEq(token.balanceOf(address(user)), userAssetBefore + receivedAmount);
                assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore - fillAmount);
                assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore + fillAmount);
            }
        }
    }

    function testFulfillOrder(uint256 orderAmount, uint256 receivedAmount) public {
        OrderProcessor.OrderRequest memory order = dummyOrder;
        order.quantityIn = orderAmount;
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.paymentToken, order.quantityIn);
        uint256 fees = flatFee + percentageFee;
        vm.assume(fees < orderAmount);
        uint256 fillAmount = orderAmount - fees;

        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

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
        issuer.fillOrder(order, salt, fillAmount, receivedAmount);
        assertEq(issuer.getRemainingOrder(orderId), 0);
        assertEq(issuer.numOpenOrders(), 0);
        assertEq(issuer.getTotalReceived(orderId), 0);
        // balances after
        assertEq(token.balanceOf(address(user)), userAssetBefore + receivedAmount);
        assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore - fillAmount - fees);
        assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore + fillAmount);
        assertEq(paymentToken.balanceOf(treasury), treasuryPaymentBefore + fees);
    }

    function testFillorderNoOrderReverts() public {
        vm.expectRevert(OrderProcessor.OrderNotFound.selector);
        vm.prank(operator);
        issuer.fillOrder(dummyOrder, salt, 100, 100);
    }

    function testRequestCancel() public {
        paymentToken.mint(user, dummyOrder.quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), dummyOrder.quantityIn);

        vm.prank(user);
        issuer.requestOrder(dummyOrder, salt);

        bytes32 orderId = issuer.getOrderIdFromOrderRequest(dummyOrder, salt);
        vm.expectEmit(true, true, true, true);
        emit CancelRequested(orderId, user);
        vm.prank(user);
        issuer.requestCancel(dummyOrder, salt);
    }

    function testRequestCancelNotRequesterReverts() public {
        paymentToken.mint(user, dummyOrder.quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), dummyOrder.quantityIn);

        vm.prank(user);
        issuer.requestOrder(dummyOrder, salt);

        vm.expectRevert(OrderProcessor.NotRequester.selector);
        issuer.requestCancel(dummyOrder, salt);
    }

    function testRequestCancelNotFoundReverts() public {
        vm.expectRevert(OrderProcessor.OrderNotFound.selector);
        vm.prank(user);
        issuer.requestCancel(dummyOrder, salt);
    }

    function testCancelOrder(uint256 inputAmount, uint256 fillAmount, string calldata reason) public {
        vm.assume(inputAmount > 0);

        OrderProcessor.OrderRequest memory order = dummyOrder;
        order.quantityIn = inputAmount;
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.paymentToken, order.quantityIn);
        uint256 fees = flatFee + percentageFee;
        vm.assume(fees < inputAmount);
        uint256 orderAmount = inputAmount - fees;
        vm.assume(fillAmount < orderAmount);

        paymentToken.mint(user, inputAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), inputAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        if (fillAmount > 0) {
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, 100);
        }

        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);

        // balances before
        uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(orderId, user, reason);
        vm.prank(operator);
        issuer.cancelOrder(order, salt, reason);
        // balances after
        if (fillAmount > 0) {
            // uint256 feesEarned = percentageFee * fillAmount / (orderAmount - fees) + flatFee;
            uint256 feesEarned = PrbMath.mulDiv(percentageFee, fillAmount, orderAmount) + flatFee;
            uint256 escrow = inputAmount - fillAmount;
            assertEq(paymentToken.balanceOf(address(user)), escrow - feesEarned);
            assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore - escrow);
            assertEq(paymentToken.balanceOf(treasury), feesEarned);
        } else {
            assertEq(paymentToken.balanceOf(address(user)), inputAmount);
            assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore - inputAmount);
        }
    }

    function testCancelOrderNotFoundReverts() public {
        vm.expectRevert(OrderProcessor.OrderNotFound.selector);
        vm.prank(operator);
        issuer.cancelOrder(dummyOrder, salt, "msg");
    }
}
