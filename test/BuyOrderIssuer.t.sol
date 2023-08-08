// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";
import "./utils/mocks/MockdShare.sol";
import "./utils/SigUtils.sol";
import "../src/issuer/BuyOrderIssuer.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {TokenLockCheck, ITokenLockCheck} from "../src/TokenLockCheck.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract BuyOrderIssuerTest is Test {
    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees indexed orderFees);
    event OrdersPaused(bool paused);

    event OrderRequested(address indexed recipient, uint256 indexed index, IOrderBridge.Order order);
    event OrderFill(address indexed recipient, uint256 indexed index, uint256 fillAmount, uint256 receivedAmount);
    event OrderFulfilled(address indexed recipient, uint256 indexed index);
    event CancelRequested(address indexed recipient, uint256 indexed index);
    event OrderCancelled(address indexed recipient, uint256 indexed index, string reason);

    dShare token;
    OrderFees orderFees;
    BuyOrderIssuer issuer;
    MockToken paymentToken;
    SigUtils sigUtils;
    TokenLockCheck tokenLockCheck;

    uint256 userPrivateKey;
    address user;

    address constant operator = address(3);
    address constant treasury = address(4);

    uint256 flatFee;
    uint64 percentageFeeRate;
    IOrderBridge.OrderRequest dummyOrderRequest;
    uint256 dummyOrderFees;
    IOrderBridge.Order dummyOrder;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockdShare();
        paymentToken = new MockToken();
        sigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());

        orderFees = new OrderFees(address(this), 1 ether, 0.005 ether);

        
        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(paymentToken));
        issuer = new BuyOrderIssuer(address(this), treasury, orderFees, tokenLockCheck);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);

        dummyOrderRequest = IOrderBridge.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: 100 ether,
            price: 0
        });
        (flatFee, percentageFeeRate) = issuer.getFeeRatesForOrder(address(paymentToken));
        dummyOrderFees = issuer.estimateTotalFees(flatFee, percentageFeeRate, dummyOrderRequest.quantityIn);
        dummyOrder = IOrderBridge.Order({
            recipient: user,
            index: 0,
            quantityIn: dummyOrderRequest.quantityIn,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderBridge.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: dummyOrderRequest.quantityIn - dummyOrderFees,
            price: 0,
            tif: IOrderBridge.TIF.GTC
        });
    }


    function testDeploymentZeroTreasuryReverts() public {
        vm.expectRevert(OrderProcessor.ZeroAddress.selector);
        new BuyOrderIssuer(address(this), address(0), orderFees, tokenLockCheck);
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

        (uint256 inputValue, uint256 _flatFee, uint256 percentageFee) =
            issuer.getInputValueForOrderValue(address(paymentToken), value);
        assertEq(inputValue, value);
        assertEq(_flatFee, 0);
        assertEq(percentageFee, 0);
        (uint256 flatFee2, uint256 percentageFee2) = issuer.getFeeRatesForOrder(address(paymentToken));
        assertEq(flatFee2, 0);
        assertEq(percentageFee2, 0);
    }

    function testGetInputValue(uint64 perOrderFee, uint64 _percentageFeeRate, uint128 orderValue) public {
        // uint128 used to avoid overflow when calculating larger raw input value
        vm.assume(_percentageFeeRate < 1 ether);
        OrderFees fees = new OrderFees(address(this), perOrderFee, _percentageFeeRate);
        issuer.setOrderFees(fees);

        (uint256 inputValue, uint256 _flatFee, uint256 percentageFee) =
            issuer.getInputValueForOrderValue(address(paymentToken), orderValue);
        assertEq(inputValue - _flatFee - percentageFee, orderValue);
        (uint256 flatFee2, uint64 percentageFeeRate2) = issuer.getFeeRatesForOrder(address(paymentToken));
        uint256 totalFees = issuer.estimateTotalFees(flatFee2, percentageFeeRate2, inputValue);
        assertEq(_flatFee, flatFee2);
        assertEq(totalFees, _flatFee + percentageFee);
    }

    function testSetOrdersPaused(bool pause) public {
        vm.expectEmit(true, true, true, true);
        emit OrdersPaused(pause);
        issuer.setOrdersPaused(pause);
        assertEq(issuer.ordersPaused(), pause);
    }

    function testRequestOrder(uint256 quantityIn) public {
        IOrderBridge.OrderRequest memory orderRequest = dummyOrderRequest;
        orderRequest.quantityIn = quantityIn;

        uint256 fees = issuer.estimateTotalFees(flatFee, percentageFeeRate, orderRequest.quantityIn);

        IOrderBridge.Order memory order = dummyOrder;
        order.quantityIn = quantityIn;
        order.paymentTokenQuantity = 0;
        if (quantityIn > fees) {
            order.paymentTokenQuantity = quantityIn - fees;
        }

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);
        if (quantityIn == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(user);
            issuer.requestOrder(orderRequest);
        } else if (fees >= quantityIn) {
            vm.expectRevert(BuyOrderIssuer.OrderTooSmall.selector);
            vm.prank(user);
            issuer.requestOrder(orderRequest);
        } else {
            // balances before
            uint256 userBalanceBefore = paymentToken.balanceOf(user);
            uint256 issuerBalanceBefore = paymentToken.balanceOf(address(issuer));
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(user, order.index, order);
            vm.prank(user);
            uint256 index = issuer.requestOrder(orderRequest);
            assertEq(index, order.index);
            assertTrue(issuer.isOrderActive(id));
            assertEq(issuer.getRemainingOrder(id), quantityIn - fees);
            assertEq(issuer.numOpenOrders(), 1);
            // balances after
            assertEq(paymentToken.balanceOf(address(user)), userBalanceBefore - quantityIn);
            assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + quantityIn);
        }
    }

    function testRequestOrderZeroAddressReverts() public {
        OrderProcessor.OrderRequest memory orderRequest = dummyOrderRequest;
        orderRequest.recipient = address(0);

        vm.expectRevert(OrderProcessor.ZeroAddress.selector);
        vm.prank(user);
        issuer.requestOrder(orderRequest);
    }

    function testRequestOrderPausedReverts() public {
        issuer.setOrdersPaused(true);

        vm.expectRevert(OrderProcessor.Paused.selector);
        vm.prank(user);
        issuer.requestOrder(dummyOrderRequest);
    }

    function testRequestOrderBlacklist(uint256 quantityIn) public {
        // restrict msg.sender
        TransferRestrictor(address(token.transferRestrictor())).restrict(user);
        uint256 fees = issuer.estimateTotalFees(flatFee, percentageFeeRate, quantityIn);
        vm.assume(quantityIn > 0);
        vm.assume(quantityIn > fees);

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.expectRevert(OrderProcessor.Blacklist.selector);
        vm.prank(user);
        issuer.requestOrder(dummyOrderRequest);
    }

    function testPaymentTokenBlackList(uint256 quantityIn) public {
        uint256 fees = issuer.estimateTotalFees(flatFee, percentageFeeRate, quantityIn);
        vm.assume(quantityIn > 0);
        vm.assume(quantityIn > fees);

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        paymentToken.blacklist(user);
        assertEq(tokenLockCheck.isTransferLocked(address(paymentToken), user), true);

        vm.expectRevert(OrderProcessor.Blacklist.selector);
        vm.prank(user);
        issuer.requestOrder(dummyOrderRequest);
    }

    function testRequestOrderUnsupportedPaymentReverts() public {
        MockToken tryPaymentToken = new MockToken();
        vm.assume(!issuer.hasRole(issuer.PAYMENTTOKEN_ROLE(), address(tryPaymentToken)));

        IOrderBridge.OrderRequest memory order = dummyOrderRequest;
        order.paymentToken = address(tryPaymentToken);

        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(address(tryPaymentToken)),
                    " is missing role ",
                    Strings.toHexString(uint256(issuer.PAYMENTTOKEN_ROLE()), 32)
                )
            )
        );
        vm.prank(user);
        issuer.requestOrder(order);
    }

    function testBlackListAssetRevert() public {
        TransferRestrictor(address(token.transferRestrictor())).restrict(dummyOrder.recipient);
        vm.expectRevert(OrderProcessor.Blacklist.selector);
        vm.prank(user);
        issuer.requestOrder(dummyOrderRequest);
    }

    function testRequestOrderUnsupportedAssetReverts() public {
        dShare tryAssetToken = new MockdShare();
        vm.assume(!issuer.hasRole(issuer.ASSETTOKEN_ROLE(), address(tryAssetToken)));

        IOrderBridge.OrderRequest memory order = dummyOrderRequest;
        order.assetToken = address(tryAssetToken);

        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(address(tryAssetToken)),
                    " is missing role ",
                    Strings.toHexString(uint256(issuer.ASSETTOKEN_ROLE()), 32)
                )
            )
        );
        vm.prank(user);
        issuer.requestOrder(order);
    }

    function testRequestOrderWithPermit() public {
        paymentToken.mint(user, dummyOrderRequest.quantityIn);

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: user,
            spender: address(issuer),
            value: dummyOrderRequest.quantityIn,
            nonce: 0,
            deadline: 30 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            issuer.selfPermit.selector, address(paymentToken), permit.value, permit.deadline, v, r, s
        );
        calls[1] = abi.encodeWithSelector(OrderProcessor.requestOrder.selector, dummyOrderRequest);

        bytes32 id = issuer.getOrderId(dummyOrder.recipient, dummyOrder.index);

        // balances before
        uint256 userBalanceBefore = paymentToken.balanceOf(user);
        uint256 issuerBalanceBefore = paymentToken.balanceOf(address(issuer));
        vm.expectEmit(true, true, true, true);
        emit OrderRequested(user, dummyOrder.index, dummyOrder);
        vm.prank(user);
        issuer.multicall(calls);
        assertEq(paymentToken.nonces(user), 1);
        assertEq(paymentToken.allowance(user, address(issuer)), 0);
        assertTrue(issuer.isOrderActive(id));
        assertEq(issuer.getRemainingOrder(id), dummyOrderRequest.quantityIn - dummyOrderFees);
        assertEq(issuer.numOpenOrders(), 1);
        // balances after
        assertEq(paymentToken.balanceOf(address(user)), userBalanceBefore - dummyOrderRequest.quantityIn);
        assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + dummyOrderRequest.quantityIn);
    }

    function testFillOrder(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount) public {
        IOrderBridge.OrderRequest memory orderRequest = dummyOrderRequest;
        orderRequest.quantityIn = orderAmount;
        uint256 fees = issuer.estimateTotalFees(flatFee, percentageFeeRate, orderRequest.quantityIn);
        vm.assume(fees < orderAmount);

        IOrderBridge.Order memory order = dummyOrder;
        order.quantityIn = orderAmount;
        order.paymentTokenQuantity = orderAmount - fees;
        uint256 feesEarned = 0;
        if (fillAmount > 0) {
            feesEarned = flatFee + PrbMath.mulDiv(fees - flatFee, fillAmount, order.paymentTokenQuantity);
        }

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(orderRequest);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount - fees) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        } else {
            // balances before
            uint256 userAssetBefore = token.balanceOf(user);
            uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
            uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
            vm.expectEmit(true, true, true, true);
            emit OrderFill(order.recipient, order.index, fillAmount, receivedAmount);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
            assertEq(issuer.getRemainingOrder(id), orderAmount - fees - fillAmount);
            // balances after
            assertEq(token.balanceOf(address(user)), userAssetBefore + receivedAmount);
            assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore - fillAmount - feesEarned);
            assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore + fillAmount);
            assertEq(paymentToken.balanceOf(treasury), feesEarned);
            if (fillAmount == orderAmount - fees) {
                assertEq(issuer.numOpenOrders(), 0);
                assertEq(issuer.getTotalReceived(id), 0);
            } else {
                assertEq(issuer.getTotalReceived(id), receivedAmount);
            }
        }
    }

    function testFulfillOrder(uint256 orderAmount, uint256 receivedAmount) public {
        IOrderBridge.OrderRequest memory orderRequest = dummyOrderRequest;
        orderRequest.quantityIn = orderAmount;
        uint256 fees = issuer.estimateTotalFees(flatFee, percentageFeeRate, orderRequest.quantityIn);
        vm.assume(fees < orderAmount);

        uint256 fillAmount = orderAmount - fees;
        IOrderBridge.Order memory order = dummyOrder;
        order.quantityIn = orderAmount;
        order.paymentTokenQuantity = fillAmount;

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(orderRequest);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);

        // balances before
        uint256 userAssetBefore = token.balanceOf(user);
        uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
        uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
        uint256 treasuryPaymentBefore = paymentToken.balanceOf(treasury);
        vm.expectEmit(true, true, true, true);
        emit OrderFulfilled(order.recipient, order.index);
        vm.prank(operator);
        issuer.fillOrder(order, fillAmount, receivedAmount);
        assertEq(issuer.getRemainingOrder(id), 0);
        assertEq(issuer.numOpenOrders(), 0);
        assertEq(issuer.getTotalReceived(id), 0);
        // balances after
        assertEq(token.balanceOf(address(user)), userAssetBefore + receivedAmount);
        assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore - fillAmount - fees);
        assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore + fillAmount);
        assertEq(paymentToken.balanceOf(treasury), treasuryPaymentBefore + fees);
    }

    function testFillorderNoOrderReverts() public {
        vm.expectRevert(OrderProcessor.OrderNotFound.selector);
        vm.prank(operator);
        issuer.fillOrder(dummyOrder, 100, 100);
    }

    function testRequestCancel() public {
        paymentToken.mint(user, dummyOrderRequest.quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), dummyOrderRequest.quantityIn);

        vm.prank(user);
        issuer.requestOrder(dummyOrderRequest);

        vm.expectEmit(true, true, true, true);
        emit CancelRequested(dummyOrder.recipient, dummyOrder.index);
        vm.prank(user);
        issuer.requestCancel(dummyOrder.recipient, dummyOrder.index);

        vm.expectRevert(OrderProcessor.OrderCancellationInitiated.selector);
        vm.prank(user);
        issuer.requestCancel(dummyOrder.recipient, dummyOrder.index);
        assertEq(issuer.cancelRequested(issuer.getOrderId(dummyOrder.recipient, dummyOrder.index)), true);
    }

    function testRequestCancelNotRequesterReverts() public {
        paymentToken.mint(user, dummyOrderRequest.quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), dummyOrderRequest.quantityIn);

        vm.prank(user);
        issuer.requestOrder(dummyOrderRequest);

        vm.expectRevert(OrderProcessor.NotRequester.selector);
        issuer.requestCancel(dummyOrder.recipient, dummyOrder.index);
    }

    function testRequestCancelNotFoundReverts() public {
        vm.expectRevert(OrderProcessor.OrderNotFound.selector);
        vm.prank(user);
        issuer.requestCancel(dummyOrder.recipient, dummyOrder.index);
    }

    function testCancelOrder(uint256 inputAmount, uint256 fillAmount, string calldata reason) public {
        vm.assume(inputAmount > 0);

        IOrderBridge.OrderRequest memory orderRequest = dummyOrderRequest;
        orderRequest.quantityIn = inputAmount;
        uint256 fees = issuer.estimateTotalFees(flatFee, percentageFeeRate, orderRequest.quantityIn);
        vm.assume(fees < inputAmount);
        uint256 orderAmount = inputAmount - fees;
        vm.assume(fillAmount < orderAmount);

        IOrderBridge.Order memory order = dummyOrder;
        order.quantityIn = inputAmount;
        order.paymentTokenQuantity = orderAmount;

        paymentToken.mint(user, inputAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), inputAmount);

        vm.prank(user);
        issuer.requestOrder(orderRequest);

        uint256 feesEarned = 0;
        if (fillAmount > 0) {
            feesEarned = flatFee + PrbMath.mulDiv(fees - flatFee, fillAmount, order.paymentTokenQuantity);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, 100);
        }

        // balances before
        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(order.recipient, order.index, reason);
        vm.prank(operator);
        issuer.cancelOrder(order, reason);
        assertEq(paymentToken.balanceOf(address(issuer)), 0);
        assertEq(paymentToken.balanceOf(treasury), feesEarned);
        // balances after
        if (fillAmount > 0) {
            assertEq(paymentToken.balanceOf(address(user)), inputAmount - fillAmount - feesEarned);
        } else {
            assertEq(paymentToken.balanceOf(address(user)), inputAmount);
        }
    }

    function testCancelOrderNotFoundReverts() public {
        vm.expectRevert(OrderProcessor.OrderNotFound.selector);
        vm.prank(operator);
        issuer.cancelOrder(dummyOrder, "msg");
    }
}
