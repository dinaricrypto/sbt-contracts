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
    event OrderRequested(bytes32 indexed id, address indexed user, IVaultBridge.Order order);
    event OrderFilled(
        bytes32 indexed id, address indexed user, bool sell, uint256 assetTokenQuantity, uint256 paymentTokenQuantity
    );
    event OrderClosed(bytes32 indexed id, address indexed user);

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
            amount: 100,
            tif: 0
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

    function testRequestOrder(bool sell, uint8 orderType, uint256 amount) public {
        vm.assume(orderType < 2);

        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        IVaultBridge.Order memory order = IVaultBridge.Order({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: sell,
            orderType: IVaultBridge.OrderType(orderType),
            amount: amount,
            tif: 0
        });
        bytes32 orderId = bridge.getOrderId(order, salt);

        paymentToken.mint(user, amount);
        token.mint(user, amount);

        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), amount);
        vm.prank(user);
        token.increaseAllowance(address(bridge), amount);

        if (orderType != 0) {
            vm.expectRevert(VaultBridge.NotImplemented.selector);
            vm.prank(user);
            bridge.requestOrder(order, salt);
        } else if (amount == 0) {
            vm.expectRevert(VaultBridge.ZeroValue.selector);
            vm.prank(user);
            bridge.requestOrder(order, salt);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(orderId, user, order);
            vm.prank(user);
            bridge.requestOrder(order, salt);
            assertTrue(bridge.isOrderActive(orderId));
            assertEq(bridge.getUnfilledAmount(orderId), amount);
        }
    }

    function testRequestOrderPausedReverts() public {
        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;

        bridge.setOrdersPaused(true);

        vm.expectRevert(VaultBridge.Paused.selector);
        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);
    }

    function testRequestOrderProxyOrderReverts() public {
        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;

        vm.expectRevert(VaultBridge.NoProxyOrders.selector);
        bridge.requestOrder(dummyOrder, salt);
    }

    function testRequestOrderUnsupportedPaymentReverts(address tryPaymentToken) public {
        vm.assume(!bridge.paymentTokenEnabled(tryPaymentToken));

        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        IVaultBridge.Order memory order = dummyOrder;
        order.paymentToken = tryPaymentToken;

        vm.expectRevert(VaultBridge.UnsupportedPaymentToken.selector);
        vm.prank(user);
        bridge.requestOrder(order, salt);
    }

    function testRequestOrderCollisionReverts() public {
        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;

        paymentToken.mint(user, 10000);

        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), 10000);

        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);

        vm.expectRevert(VaultBridge.DuplicateOrder.selector);
        vm.prank(user);
        bridge.requestOrder(dummyOrder, salt);
    }

    function testFulfillOrder(bool sell, uint256 orderAmount, uint256 fillAmount, uint256 proceeds) public {
        vm.assume(orderAmount > 0);

        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        IVaultBridge.Order memory order = dummyOrder;
        order.sell = sell;
        order.amount = orderAmount;
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

        uint256 assetAmount = sell ? fillAmount : proceeds;
        uint256 paymentAmount = sell ? proceeds : fillAmount;
        if (fillAmount > orderAmount) {
            vm.expectRevert(VaultBridge.FillTooLarge.selector);
            vm.prank(bridgeOperator);
            bridge.fulfillOrder(order, salt, assetAmount, paymentAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderFilled(orderId, user, sell, assetAmount, paymentAmount);
            vm.prank(bridgeOperator);
            bridge.fulfillOrder(order, salt, assetAmount, paymentAmount);
        }
    }

    function testFulfillorderNoOrderReverts() public {
        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;

        vm.expectRevert(VaultBridge.OrderNotFound.selector);
        vm.prank(bridgeOperator);
        bridge.fulfillOrder(dummyOrder, salt, 100, 100);
    }
}
