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
import {NumberUtils} from "./utils/NumberUtils.sol";
import {FeeLib} from "../src/FeeLib.sol";

contract BuyOrderIssuerTest is Test {
    event TreasurySet(address indexed treasury);
    event OrderFeesSet(IOrderFees indexed orderFees);
    event OrdersPaused(bool paused);
    event TokenLockCheckSet(ITokenLockCheck indexed tokenLockCheck);

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
    uint24 percentageFeeRate;
    uint256 dummyOrderFees;
    IOrderBridge.Order dummyOrder;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockdShare();
        paymentToken = new MockToken();
        sigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());

        orderFees = new OrderFees(address(this), 1 ether, 5_000);

        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(paymentToken));

        issuer = new BuyOrderIssuer(address(this), treasury, orderFees, tokenLockCheck);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);

        (flatFee, percentageFeeRate) = issuer.getFeeRatesForOrder(address(paymentToken));
        dummyOrderFees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, 100 ether);
        dummyOrder = IOrderBridge.Order({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderBridge.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 100 ether,
            price: 0,
            tif: IOrderBridge.TIF.GTC
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

    function testSetTokenLockCheck(ITokenLockCheck _tokenLockCheck) public {
        vm.expectEmit(true, true, true, true);
        emit TokenLockCheckSet(_tokenLockCheck);
        issuer.setTokenLockCheck(_tokenLockCheck);
        assertEq(address(issuer.tokenLockCheck()), address(_tokenLockCheck));
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

    function testGetInputValue(uint24 perOrderFee, uint24 _percentageFeeRate, uint128 orderValue) public {
        // uint128 used to avoid overflow when calculating larger raw input value
        vm.assume(_percentageFeeRate < 1_000_000);
        OrderFees fees = new OrderFees(address(this), perOrderFee, _percentageFeeRate);
        issuer.setOrderFees(fees);
        (uint256 inputValue, uint256 _flatFee, uint256 percentageFee) =
            issuer.getInputValueForOrderValue(address(paymentToken), orderValue);
        assertEq(inputValue - _flatFee - percentageFee, orderValue);
        (uint256 flatFee2, uint24 percentageFeeRate2) = issuer.getFeeRatesForOrder(address(paymentToken));
        uint256 totalFees = FeeLib.estimateTotalFees(flatFee2, percentageFeeRate2, inputValue);
        assertEq(_flatFee, flatFee2);
        assertEq(totalFees, _flatFee + percentageFee);
    }

    function testSetOrdersPaused(bool pause) public {
        vm.expectEmit(true, true, true, true);
        emit OrdersPaused(pause);
        issuer.setOrdersPaused(pause);
        assertEq(issuer.ordersPaused(), pause);
    }

    function testRequestOrder(uint256 orderAmount) public {
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));

        IOrderBridge.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;
        uint256 quantityIn = order.paymentTokenQuantity + fees;

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        bytes32 id = issuer.getOrderId(order.recipient, 0);
        if (orderAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(user);
            issuer.requestOrder(order);
        } else {
            // balances before
            uint256 userBalanceBefore = paymentToken.balanceOf(user);
            uint256 issuerBalanceBefore = paymentToken.balanceOf(address(issuer));
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(user, 0, order);
            vm.prank(user);
            uint256 index = issuer.requestOrder(order);
            assertEq(index, 0);
            assertTrue(issuer.isOrderActive(id));
            assertEq(issuer.getRemainingOrder(id), order.paymentTokenQuantity);
            assertEq(issuer.numOpenOrders(), 1);
            // balances after
            assertEq(paymentToken.balanceOf(address(user)), userBalanceBefore - (quantityIn));
            assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + (quantityIn));
            assertEq(issuer.escrowedBalanceOf(order.paymentToken, user), quantityIn);
        }
    }

    function testRequestOrderZeroAddressReverts() public {
        IOrderBridge.Order memory order = dummyOrder;
        order.recipient = address(0);

        vm.expectRevert(OrderProcessor.ZeroAddress.selector);
        vm.prank(user);
        issuer.requestOrder(order);
    }

    function testRequestOrderPausedReverts() public {
        issuer.setOrdersPaused(true);

        vm.expectRevert(OrderProcessor.Paused.selector);
        vm.prank(user);
        issuer.requestOrder(dummyOrder);
    }

    function testRequestOrderBlacklist(uint256 orderAmount) public {
        vm.assume(orderAmount > 0);
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));

        IOrderBridge.Order memory order = dummyOrder;
        uint256 quantityIn = orderAmount + fees;
        order.paymentTokenQuantity = orderAmount;

        // restrict msg.sender
        TransferRestrictor(address(token.transferRestrictor())).restrict(user);

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.expectRevert(OrderProcessor.Blacklist.selector);
        vm.prank(user);
        issuer.requestOrder(dummyOrder);
    }

    function testPaymentTokenBlackList(uint256 orderAmount) public {
        vm.assume(orderAmount > 0);
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderBridge.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        paymentToken.blacklist(user);
        assertEq(tokenLockCheck.isTransferLocked(address(paymentToken), user), true);

        vm.expectRevert(OrderProcessor.Blacklist.selector);
        vm.prank(user);
        issuer.requestOrder(dummyOrder);
    }

    function testRequestOrderUnsupportedPaymentReverts() public {
        address tryPaymentToken = address(new MockToken());

        IOrderBridge.Order memory order = dummyOrder;
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
        issuer.requestOrder(order);
    }

    function testBlackListAssetRevert() public {
        TransferRestrictor(address(token.transferRestrictor())).restrict(dummyOrder.recipient);
        vm.expectRevert(OrderProcessor.Blacklist.selector);
        vm.prank(user);
        issuer.requestOrder(dummyOrder);
    }

    function testRequestOrderUnsupportedAssetReverts() public {
        address tryAssetToken = address(new MockdShare());

        IOrderBridge.Order memory order = dummyOrder;
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
        issuer.requestOrder(order);
    }

    function testRequestOrderWithPermit() public {
        uint256 quantityIn = dummyOrder.paymentTokenQuantity + dummyOrderFees;
        paymentToken.mint(user, quantityIn * 1e6);

        SigUtils.Permit memory permit =
            SigUtils.Permit({owner: user, spender: address(issuer), value: quantityIn, nonce: 0, deadline: 30 days});

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            issuer.selfPermit.selector, address(paymentToken), permit.owner, permit.value, permit.deadline, v, r, s
        );
        calls[1] = abi.encodeWithSelector(OrderProcessor.requestOrder.selector, dummyOrder);

        bytes32 id = issuer.getOrderId(dummyOrder.recipient, 0);

        // balances before
        uint256 userBalanceBefore = paymentToken.balanceOf(user);
        uint256 issuerBalanceBefore = paymentToken.balanceOf(address(issuer));
        vm.expectEmit(true, true, true, true);
        emit OrderRequested(user, 0, dummyOrder);
        vm.prank(user);
        issuer.multicall(calls);
        assertEq(paymentToken.nonces(user), 1);
        assertEq(paymentToken.allowance(user, address(issuer)), 0);
        assertTrue(issuer.isOrderActive(id));
        assertEq(issuer.getRemainingOrder(id), dummyOrder.paymentTokenQuantity);
        assertEq(issuer.numOpenOrders(), 1);
        // balances after
        assertEq(paymentToken.balanceOf(address(user)), userBalanceBefore - quantityIn);
        assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + quantityIn);
    }

    function testFillOrder(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount) public {
        vm.assume(orderAmount > 0);
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderBridge.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;

        uint256 feesEarned = 0;
        if (fillAmount > 0) {
            feesEarned = flatFee + PrbMath.mulDiv(fees - flatFee, fillAmount, order.paymentTokenQuantity);
        }

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.prank(user);
        uint256 index = issuer.requestOrder(order);

        bytes32 id = issuer.getOrderId(order.recipient, index);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, 0, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, index, fillAmount, receivedAmount);
        } else {
            // balances before
            uint256 userAssetBefore = token.balanceOf(user);
            uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
            uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
            vm.expectEmit(true, true, true, true);
            emit OrderFill(order.recipient, index, fillAmount, receivedAmount);
            vm.prank(operator);
            issuer.fillOrder(order, index, fillAmount, receivedAmount);
            assertEq(issuer.getRemainingOrder(id), orderAmount - fillAmount);
            // balances after
            assertEq(token.balanceOf(address(user)), userAssetBefore + receivedAmount);
            assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore - fillAmount - feesEarned);
            assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore + fillAmount);
            assertEq(paymentToken.balanceOf(treasury), feesEarned);
            if (fillAmount == orderAmount) {
                assertEq(issuer.numOpenOrders(), 0);
                assertEq(issuer.getTotalReceived(id), 0);
            } else {
                assertEq(issuer.getTotalReceived(id), receivedAmount);
                assertEq(issuer.escrowedBalanceOf(order.paymentToken, user), quantityIn - feesEarned - fillAmount);
            }
        }
    }

    function testFulfillOrder(uint256 orderAmount, uint256 receivedAmount) public {
        vm.assume(orderAmount > 0);
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderBridge.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.prank(user);
        uint256 index = issuer.requestOrder(order);

        bytes32 id = issuer.getOrderId(order.recipient, index);

        // balances before
        uint256 userAssetBefore = token.balanceOf(user);
        uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
        uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
        uint256 treasuryPaymentBefore = paymentToken.balanceOf(treasury);
        vm.expectEmit(true, true, true, true);
        emit OrderFulfilled(order.recipient, index);
        vm.prank(operator);
        issuer.fillOrder(order, index, orderAmount, receivedAmount);
        assertEq(issuer.getRemainingOrder(id), 0);
        assertEq(issuer.numOpenOrders(), 0);
        assertEq(issuer.getTotalReceived(id), 0);
        // balances after
        assertEq(token.balanceOf(address(user)), userAssetBefore + receivedAmount);
        assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore - quantityIn);
        assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore + orderAmount);
        assertEq(paymentToken.balanceOf(treasury), treasuryPaymentBefore + fees);
    }

    function testFillorderNoOrderReverts(uint256 index) public {
        vm.expectRevert(OrderProcessor.OrderNotFound.selector);
        vm.prank(operator);
        issuer.fillOrder(dummyOrder, index, 100, 100);
    }

    function testRequestCancel() public {
        uint256 quantityIn = dummyOrder.paymentTokenQuantity + dummyOrderFees;
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.prank(user);
        uint256 index = issuer.requestOrder(dummyOrder);

        vm.expectEmit(true, true, true, true);
        emit CancelRequested(dummyOrder.recipient, index);
        vm.prank(user);
        issuer.requestCancel(dummyOrder.recipient, index);

        vm.expectRevert(OrderProcessor.OrderCancellationInitiated.selector);
        vm.prank(user);
        issuer.requestCancel(dummyOrder.recipient, index);
        assertEq(issuer.cancelRequested(issuer.getOrderId(dummyOrder.recipient, index)), true);
    }

    function testRequestCancelNotRequesterReverts() public {
        uint256 quantityIn = dummyOrder.paymentTokenQuantity + dummyOrderFees;
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.prank(user);
        uint256 index = issuer.requestOrder(dummyOrder);

        vm.expectRevert(OrderProcessor.NotRequester.selector);
        issuer.requestCancel(dummyOrder.recipient, index);
    }

    function testRequestCancelNotFoundReverts(uint256 index) public {
        vm.expectRevert(OrderProcessor.OrderNotFound.selector);
        vm.prank(user);
        issuer.requestCancel(dummyOrder.recipient, index);
    }

    function testCancelOrder(uint256 orderAmount, uint256 fillAmount, string calldata reason) public {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount < orderAmount);
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderBridge.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.prank(user);
        uint256 index = issuer.requestOrder(order);

        uint256 feesEarned = 0;
        if (fillAmount > 0) {
            feesEarned = flatFee + PrbMath.mulDiv(fees - flatFee, fillAmount, order.paymentTokenQuantity);
            vm.prank(operator);
            issuer.fillOrder(order, index, fillAmount, 100);
        }

        // balances before
        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(order.recipient, index, reason);
        vm.prank(operator);
        issuer.cancelOrder(order, index, reason);
        assertEq(paymentToken.balanceOf(address(issuer)), 0);
        assertEq(paymentToken.balanceOf(treasury), feesEarned);
        // balances after
        assertEq(issuer.escrowedBalanceOf(order.paymentToken, user), 0);
        if (fillAmount > 0) {
            assertEq(paymentToken.balanceOf(address(user)), quantityIn - fillAmount - feesEarned);
        } else {
            assertEq(paymentToken.balanceOf(address(user)), quantityIn);
        }
    }

    function testCancelOrderNotFoundReverts(uint256 index) public {
        vm.expectRevert(OrderProcessor.OrderNotFound.selector);
        vm.prank(operator);
        issuer.cancelOrder(dummyOrder, index, "msg");
    }
}
