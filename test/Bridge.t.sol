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
    event FeesSet(Bridge.Fees fees);
    event PaymentTokenEnabled(address indexed token, bool enabled);
    event OrdersPaused(bool paused);
    event SwapSubmitted(bytes32 indexed swapId, address indexed user, Bridge.Swap swap, uint256 orderAmount);
    event SwapFulfilled(bytes32 indexed swapId, address indexed user, uint256 amount);

    BridgedERC20 token;
    Bridge bridge;
    MockERC20 paymentToken;

    address constant user = address(1);
    address constant bridgeOperator = address(3);
    address constant treasury = address(4);

    function setUp() public {
        token = new MockBridgedERC20();
        paymentToken = new MockERC20("Money", "$", 18);
        Bridge bridgeImpl = new Bridge();
        bridge = Bridge(
            address(new ERC1967Proxy(address(bridgeImpl), abi.encodeCall(Bridge.initialize, (address(this), treasury))))
        );

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
            Bridge(address(new ERC1967Proxy(address(bridgeImpl), abi.encodeCall(Bridge.initialize, (owner, treasury)))));
        assertEq(newBridge.owner(), owner);

        Bridge newImpl = new Bridge();
        vm.expectRevert(Ownable.Unauthorized.selector);
        newBridge.upgradeToAndCall(address(newImpl), abi.encodeCall(Bridge.initialize, (owner, treasury)));
    }

    function testSetTreasury(address account) public {
        vm.expectEmit(true, true, true, true);
        emit TreasurySet(account);
        bridge.setTreasury(account);
        assertEq(bridge.treasury(), account);
    }

    function testSetFees(Bridge.Fees calldata fees) public {
        if (fees.purchaseFee > 1 ether || fees.saleFee > 1 ether) {
            vm.expectRevert(Bridge.FeeTooLarge.selector);
            bridge.setFees(fees);
        } else {
            vm.expectEmit(true, true, true, true);
            emit FeesSet(fees);
            bridge.setFees(fees);
            (uint128 purchaseFee, uint128 saleFee) = bridge.fees();
            assertEq(purchaseFee, fees.purchaseFee);
            assertEq(saleFee, fees.saleFee);
        }
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

    function testSubmitSwap(bool buy, uint256 amount, uint64 fee) public {
        vm.assume(fee < 1 ether);

        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        Bridge.Swap memory swap = Bridge.Swap({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            action: buy ? Bridge.OrderAction.BUY : Bridge.OrderAction.SELL,
            amount: amount
        });
        bytes32 swapId = bridge.hashSwapTicket(swap, salt);

        paymentToken.mint(user, amount);
        token.mint(user, amount);

        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), amount);
        vm.prank(user);
        token.increaseAllowance(address(bridge), amount);

        bridge.setFees(Bridge.Fees({purchaseFee: fee, saleFee: fee}));

        if (amount == 0) {
            vm.expectRevert(Bridge.ZeroValue.selector);
            vm.prank(user);
            bridge.submitSwap(swap, salt);
        } else {
            vm.expectEmit(true, true, true, true);
            emit SwapSubmitted(swapId, user, swap, buy ? amount - PrbMath.mulDiv18(amount, fee) : amount);
            vm.prank(user);
            bridge.submitSwap(swap, salt);
            assertTrue(bridge.isSwapActive(swapId));
        }
    }

    function testSubmitSwapPausedReverts() public {
        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        Bridge.Swap memory swap = Bridge.Swap({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            action: Bridge.OrderAction.BUY,
            amount: 100
        });

        bridge.setOrdersPaused(true);

        vm.expectRevert(Bridge.Paused.selector);
        vm.prank(user);
        bridge.submitSwap(swap, salt);
    }

    function testSubmitSwapProxyOrderReverts() public {
        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        Bridge.Swap memory swap = Bridge.Swap({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            action: Bridge.OrderAction.BUY,
            amount: 100
        });

        vm.expectRevert(Bridge.NoProxyOrders.selector);
        bridge.submitSwap(swap, salt);
    }

    function testSubmitSwapUnsupportedPaymentReverts(address tryPaymentToken) public {
        vm.assume(!bridge.paymentTokenEnabled(tryPaymentToken));

        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        Bridge.Swap memory swap = Bridge.Swap({
            user: user,
            assetToken: address(token),
            paymentToken: tryPaymentToken,
            action: Bridge.OrderAction.BUY,
            amount: 100
        });

        vm.expectRevert(Bridge.UnsupportedPaymentToken.selector);
        vm.prank(user);
        bridge.submitSwap(swap, salt);
    }

    function testSubmitSwapCollisionReverts() public {
        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        Bridge.Swap memory swap = Bridge.Swap({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            action: Bridge.OrderAction.BUY,
            amount: 100
        });

        paymentToken.mint(user, 10000);

        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), 10000);

        vm.prank(user);
        bridge.submitSwap(swap, salt);

        vm.expectRevert(Bridge.DuplicateOrder.selector);
        vm.prank(user);
        bridge.submitSwap(swap, salt);
    }

    function testFulfillSwap(bool buy, uint256 amount, uint64 fee, uint256 finalAmount) public {
        vm.assume(amount > 0);
        vm.assume(fee < 1 ether);

        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        Bridge.Swap memory swap = Bridge.Swap({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            action: buy ? Bridge.OrderAction.BUY : Bridge.OrderAction.SELL,
            amount: amount
        });
        bytes32 swapId = bridge.hashSwapTicket(swap, salt);

        if (buy) {
            paymentToken.mint(user, amount);
            vm.prank(user);
            paymentToken.increaseAllowance(address(bridge), amount);
        } else {
            token.mint(user, amount);
            vm.prank(user);
            token.increaseAllowance(address(bridge), amount);

            paymentToken.mint(bridgeOperator, finalAmount);
            vm.prank(bridgeOperator);
            paymentToken.increaseAllowance(address(bridge), finalAmount);
        }

        bridge.setFees(Bridge.Fees({purchaseFee: fee, saleFee: fee}));

        vm.prank(user);
        bridge.submitSwap(swap, salt);

        vm.expectEmit(true, true, true, true);
        emit SwapFulfilled(swapId, user, finalAmount);
        vm.prank(bridgeOperator);
        bridge.fulfillSwap(swap, salt, finalAmount);
    }

    function testFulfillSwapNoOrderReverts() public {
        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        Bridge.Swap memory swap = Bridge.Swap({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            action: Bridge.OrderAction.BUY,
            amount: 100
        });

        vm.expectRevert(Bridge.OrderNotFound.selector);
        vm.prank(bridgeOperator);
        bridge.fulfillSwap(swap, salt, 100);
    }
}
