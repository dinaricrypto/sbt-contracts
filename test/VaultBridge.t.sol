// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solady/auth/Ownable.sol";
import "solady-test/utils/mocks/MockERC20.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "../src/VaultBridge.sol";
import "../src/FlatOrderFees.sol";

contract VaultBridgeTest is Test {
    event OrderRequested(bytes32 indexed id, address indexed user, IVaultBridge.Order order, bytes32 salt);
    event OrderFill(bytes32 indexed id, address indexed user, uint256 fillAmount, uint256 proceeds);
    event OrderFulfilled(bytes32 indexed id, address indexed user, uint256 filledAmount);
    event CancelRequested(bytes32 indexed id, address indexed user);
    event OrderCancelled(bytes32 indexed id, address indexed user, string reason);

    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees orderFees);
    event PaymentTokenEnabled(address indexed token, bool enabled);
    event OrdersPaused(bool paused);

    BridgedERC20 token;
    FlatOrderFees orderFees;
    VaultBridge bridge;
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

        VaultBridge bridgeImpl = new VaultBridge();
        bridge = VaultBridge(
            address(
                new ERC1967Proxy(address(bridgeImpl), abi.encodeCall(VaultBridge.initialize, (address(this), treasury, orderFees)))
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
            orderType: IVaultBridge.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 100,
            price: 10,
            tif: IVaultBridge.TIF.GTC
        });
    }

    function testInvariants() public {
        assertEq(bridge.operatorRole(), uint256(1 << 1));
    }

    function testInitialize(address owner) public {
        vm.assume(owner != address(this));

        VaultBridge bridgeImpl = new VaultBridge();
        VaultBridge newBridge = VaultBridge(
            address(
                new ERC1967Proxy(address(bridgeImpl), abi.encodeCall(VaultBridge.initialize, (owner, treasury, orderFees)))
            )
        );
        assertEq(newBridge.owner(), owner);

        VaultBridge newImpl = new VaultBridge();
        vm.expectRevert(Ownable.Unauthorized.selector);
        newBridge.upgradeToAndCall(
            address(newImpl), abi.encodeCall(VaultBridge.initialize, (owner, treasury, orderFees))
        );
    }

    function testSetTreasury(address account) public {
        vm.expectEmit(true, true, true, true);
        emit TreasurySet(account);
        bridge.setTreasury(account);
        assertEq(bridge.treasury(), account);
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
        uint256 assetTokenQuantity,
        uint256 paymentTokenQuantity,
        uint256 price,
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
        uint256 amount = order.sell ? order.assetTokenQuantity : order.paymentTokenQuantity;

        paymentToken.mint(user, paymentTokenQuantity);
        token.mint(user, assetTokenQuantity);

        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), paymentTokenQuantity);
        vm.prank(user);
        token.increaseAllowance(address(bridge), assetTokenQuantity);

        if (amount == 0) {
            vm.expectRevert(VaultBridge.ZeroValue.selector);
            vm.prank(user);
            bridge.requestOrder(order, salt);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(orderId, user, order, salt);
            vm.prank(user);
            bridge.requestOrder(order, salt);
            assertTrue(bridge.isOrderActive(orderId));
            assertEq(bridge.getUnfilledAmount(orderId), amount);
            assertEq(bridge.numOpenOrders(), 1);
        }
    }

    function testRequestOrderPausedReverts() public {
        bridge.setOrdersPaused(true);

        vm.expectRevert(VaultBridge.Paused.selector);
        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);
    }

    function testRequestOrderProxyOrderReverts() public {
        vm.expectRevert(VaultBridge.NoProxyOrders.selector);
        bridge.requestOrder(dummyOrder, salt);
    }

    function testRequestOrderUnsupportedPaymentReverts(address tryPaymentToken) public {
        vm.assume(!bridge.paymentTokenEnabled(tryPaymentToken));

        IVaultBridge.Order memory order = dummyOrder;
        order.paymentToken = tryPaymentToken;

        vm.expectRevert(VaultBridge.UnsupportedPaymentToken.selector);
        vm.prank(user);
        bridge.requestOrder(order, salt);
    }

    function testRequestOrderCollisionReverts() public {
        paymentToken.mint(user, 10000);

        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), 10000);

        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);

        vm.expectRevert(VaultBridge.DuplicateOrder.selector);
        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);
    }

    function testFillOrder(bool sell, uint256 orderAmount, uint256 fillAmount, uint256 proceeds) public {
        vm.assume(orderAmount > 0);

        IVaultBridge.Order memory order = dummyOrder;
        order.sell = sell;
        order.assetTokenQuantity = orderAmount;
        order.paymentTokenQuantity = orderAmount;
        bytes32 orderId = bridge.getOrderId(order, salt);

        if (sell) {
            token.mint(user, orderAmount);
            vm.prank(user);
            token.increaseAllowance(address(bridge), orderAmount);

            paymentToken.mint(bridgeOperator, proceeds);
            vm.prank(bridgeOperator);
            paymentToken.increaseAllowance(address(bridge), proceeds);
        } else {
            paymentToken.mint(user, orderAmount);
            vm.prank(user);
            paymentToken.increaseAllowance(address(bridge), orderAmount);
        }

        vm.prank(user);
        bridge.requestOrder(order, salt);

        if (fillAmount > orderAmount) {
            vm.expectRevert(VaultBridge.FillTooLarge.selector);
            vm.prank(bridgeOperator);
            bridge.fillOrder(order, salt, fillAmount, proceeds);
        } else {
            vm.expectEmit(true, true, true, false);
            emit OrderFill(orderId, user, fillAmount, proceeds);
            if (fillAmount == orderAmount) {
                vm.expectEmit(true, true, true, true);
                emit OrderFulfilled(orderId, user, orderAmount);
            }
            vm.prank(bridgeOperator);
            bridge.fillOrder(order, salt, fillAmount, proceeds);
            assertEq(bridge.getUnfilledAmount(orderId), orderAmount - fillAmount);
            assertEq(bridge.numOpenOrders(), 0);
        }
    }

    function testFillorderNoOrderReverts() public {
        vm.expectRevert(VaultBridge.OrderNotFound.selector);
        vm.prank(bridgeOperator);
        bridge.fillOrder(dummyOrder, salt, 100, 100);
    }

    function testRequestCancel() public {
        paymentToken.mint(user, dummyOrder.paymentTokenQuantity);
        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), dummyOrder.paymentTokenQuantity);

        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);

        bytes32 orderId = bridge.getOrderId(dummyOrder, salt);
        vm.expectEmit(true, true, true, true);
        emit CancelRequested(orderId, user);
        vm.prank(user);
        bridge.requestCancel(dummyOrder, salt);
    }

    function testRequestCancelNoProxyReverts() public {
        paymentToken.mint(user, dummyOrder.paymentTokenQuantity);
        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), dummyOrder.paymentTokenQuantity);

        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);

        vm.expectRevert(VaultBridge.NoProxyOrders.selector);
        bridge.requestCancel(dummyOrder, salt);
    }

    function testRequestCancelNotFoundReverts() public {
        vm.expectRevert(VaultBridge.OrderNotFound.selector);
        vm.prank(user);
        bridge.requestCancel(dummyOrder, salt);
    }

    function testCancelOrder(uint256 orderAmount, uint256 fillAmount, string calldata reason) public {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount > 0);
        vm.assume(fillAmount < orderAmount);

        IVaultBridge.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;

        paymentToken.mint(user, order.paymentTokenQuantity);
        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), order.paymentTokenQuantity);

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
        vm.expectRevert(VaultBridge.OrderNotFound.selector);
        vm.prank(bridgeOperator);
        bridge.cancelOrder(dummyOrder, salt, "msg");
    }
}
