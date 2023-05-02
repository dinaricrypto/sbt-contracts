// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solady/auth/Ownable.sol";
import "solady-test/utils/mocks/MockERC20.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "../src/VaultBridge.sol";

contract VaultBridgeTest is Test {
    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees orderFees);
    event PaymentTokenEnabled(address indexed token, bool enabled);
    event OrdersPaused(bool paused);
    event SwapSubmitted(bytes32 indexed swapId, address indexed user, VaultBridge.Swap swap);
    event SwapFulfilled(bytes32 indexed swapId, address indexed user, uint256 fillAmount, uint256 proceeds);

    BridgedERC20 token;
    IOrderFees orderFees;
    VaultBridge bridge;
    MockERC20 paymentToken;

    address constant user = address(1);
    address constant bridgeOperator = address(3);
    address constant treasury = address(4);

    function setUp() public {
        token = new MockBridgedERC20();
        paymentToken = new MockERC20("Money", "$", 18);
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
    }

    function testInvariants() public {
        assertEq(bridge.operatorRole(), uint256(1 << 1));
    }

    function testInitialize(address owner) public {
        VaultBridge bridgeImpl = new VaultBridge();
        VaultBridge newBridge = VaultBridge(
            address(new ERC1967Proxy(address(bridgeImpl), abi.encodeCall(VaultBridge.initialize, (owner, treasury, orderFees))))
        );
        assertEq(newBridge.owner(), owner);

        VaultBridge newImpl = new VaultBridge();
        vm.expectRevert(Ownable.Unauthorized.selector);
        newBridge.upgradeToAndCall(address(newImpl), abi.encodeCall(VaultBridge.initialize, (owner, treasury, orderFees)));
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
        // if (fees.purchaseFee > 1 ether || fees.saleFee > 1 ether) {
        //     vm.expectRevert(VaultBridge.FeeTooLarge.selector);
        //     bridge.setFees(fees);
        // } else {
        //     vm.expectEmit(true, true, true, true);
        //     emit FeesSet(fees);
        //     bridge.setFees(fees);
        //     (uint128 purchaseFee, uint128 saleFee) = bridge.fees();
        //     assertEq(purchaseFee, fees.purchaseFee);
        //     assertEq(saleFee, fees.saleFee);
        // }
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

    function testSubmitSwap(bool sell, uint256 amount, uint64 fee) public {
        vm.assume(fee < 1 ether);

        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        VaultBridge.Swap memory swap = VaultBridge.Swap({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: sell,
            amount: amount
        });
        bytes32 swapId = bridge.hashSwapTicket(swap, salt);

        paymentToken.mint(user, amount);
        token.mint(user, amount);

        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), amount);
        vm.prank(user);
        token.increaseAllowance(address(bridge), amount);

        // bridge.setFees(VaultBridge.Fees({purchaseFee: fee, saleFee: fee}));

        if (amount == 0) {
            vm.expectRevert(VaultBridge.ZeroValue.selector);
            vm.prank(user);
            bridge.submitSwap(swap, salt);
        } else {
            vm.expectEmit(true, true, true, true);
            emit SwapSubmitted(swapId, user, swap);
            vm.prank(user);
            bridge.submitSwap(swap, salt);
            assertTrue(bridge.isSwapActive(swapId));
        }
    }

    function testSubmitSwapPausedReverts() public {
        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        VaultBridge.Swap memory swap = VaultBridge.Swap({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            amount: 100
        });

        bridge.setOrdersPaused(true);

        vm.expectRevert(VaultBridge.Paused.selector);
        vm.prank(user);
        bridge.submitSwap(swap, salt);
    }

    function testSubmitSwapProxyOrderReverts() public {
        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        VaultBridge.Swap memory swap = VaultBridge.Swap({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            amount: 100
        });

        vm.expectRevert(VaultBridge.NoProxyOrders.selector);
        bridge.submitSwap(swap, salt);
    }

    function testSubmitSwapUnsupportedPaymentReverts(address tryPaymentToken) public {
        vm.assume(!bridge.paymentTokenEnabled(tryPaymentToken));

        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        VaultBridge.Swap memory swap = VaultBridge.Swap({
            user: user,
            assetToken: address(token),
            paymentToken: tryPaymentToken,
            sell: false,
            amount: 100
        });

        vm.expectRevert(VaultBridge.UnsupportedPaymentToken.selector);
        vm.prank(user);
        bridge.submitSwap(swap, salt);
    }

    function testSubmitSwapCollisionReverts() public {
        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        VaultBridge.Swap memory swap = VaultBridge.Swap({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            amount: 100
        });

        paymentToken.mint(user, 10000);

        vm.prank(user);
        paymentToken.increaseAllowance(address(bridge), 10000);

        vm.prank(user);
        bridge.submitSwap(swap, salt);

        vm.expectRevert(VaultBridge.DuplicateOrder.selector);
        vm.prank(user);
        bridge.submitSwap(swap, salt);
    }

    function testFulfillSwap(bool sell, uint256 amount, uint64 fee, uint256 finalAmount) public {
        vm.assume(amount > 0);
        vm.assume(fee < 1 ether);
        // TODO: test partial fills and fillstoolarge

        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        VaultBridge.Swap memory swap = VaultBridge.Swap({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: sell,
            amount: amount
        });
        bytes32 swapId = bridge.hashSwapTicket(swap, salt);

        if (sell) {
            token.mint(user, amount);
            vm.prank(user);
            token.increaseAllowance(address(bridge), amount);

            paymentToken.mint(bridgeOperator, finalAmount);
            vm.prank(bridgeOperator);
            paymentToken.increaseAllowance(address(bridge), finalAmount);
        } else {
            paymentToken.mint(user, amount);
            vm.prank(user);
            paymentToken.increaseAllowance(address(bridge), amount);
        }

        // bridge.setFees(VaultBridge.Fees({purchaseFee: fee, saleFee: fee}));

        vm.prank(user);
        bridge.submitSwap(swap, salt);

        vm.expectEmit(true, true, true, true);
        emit SwapFulfilled(swapId, user, amount, finalAmount);
        vm.prank(bridgeOperator);
        bridge.fulfillSwap(swap, salt, amount, finalAmount);
    }

    function testFulfillSwapNoOrderReverts() public {
        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        VaultBridge.Swap memory swap = VaultBridge.Swap({
            user: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            amount: 100
        });

        vm.expectRevert(VaultBridge.OrderNotFound.selector);
        vm.prank(bridgeOperator);
        bridge.fulfillSwap(swap, salt, 100, 100);
    }
}