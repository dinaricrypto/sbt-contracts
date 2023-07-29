// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OrderProcessor} from "../src/issuer/OrderProcessor.sol";
import "./utils/mocks/MockdShare.sol";
import "../src/issuer/LimitBuyIssuer.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import {NumberUtils} from "./utils/NumberUtils.sol";

contract LimitBuyIssuerTest is Test {
    event OrderFill(bytes32 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount);
    event OrderRequested(bytes32 indexed id, address indexed recipient, IOrderBridge.Order order, bytes32 salt);

    dShare token;
    OrderFees orderFees;
    LimitBuyIssuer issuer;
    MockERC20 paymentToken;

    uint256 userPrivateKey;
    address user;

    address constant operator = address(3);
    address constant treasury = address(4);

    bytes32 constant salt = 0x0000000000000000000000000000000000000000000000000000000000000001;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockdShare();
        paymentToken = new MockERC20("Money", "$", 6);

        orderFees = new OrderFees(address(this), 1 ether, 0.005 ether);

        issuer = new LimitBuyIssuer(address(this), treasury, orderFees);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
    }

    function testRequestOrderLimit(uint256 orderAmount, uint256 _price) public {
        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(address(paymentToken), orderAmount);
        uint256 fees = flatFee + percentageFee;
        IOrderBridge.Order memory order = IOrderBridge.Order({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderBridge.OrderType.LIMIT,
            assetTokenQuantity: 0,
            paymentTokenQuantity: orderAmount,
            price: _price,
            tif: IOrderBridge.TIF.GTC,
            fee: fees
        });
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        bytes32 orderId = issuer.getOrderId(order, salt);

        paymentToken.mint(user, quantityIn);
        vm.startPrank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        if (orderAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(user);
            issuer.requestOrder(order, salt);
        } else {
            uint256 userBalanceBefore = paymentToken.balanceOf(user);
            uint256 issuerBalanceBefore = paymentToken.balanceOf(address(issuer));
            if (_price == 0) {
                vm.expectRevert(LimitBuyIssuer.LimitPriceNotSet.selector);
                issuer.requestOrder(order, salt);
            } else {
                vm.expectEmit(true, true, true, true);
                emit OrderRequested(orderId, user, order, salt);
                vm.prank(user);
                issuer.requestOrder(order, salt);
                assertTrue(issuer.isOrderActive(orderId));
                assertEq(issuer.getRemainingOrder(orderId), quantityIn - fees);
                assertEq(issuer.numOpenOrders(), 1);
                // balances after
                assertEq(paymentToken.balanceOf(address(user)), userBalanceBefore - quantityIn);
                assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + quantityIn);
            }
        }
    }

    function testFillBuyOrderLimit(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount, uint256 _price)
        public
    {
        vm.assume(_price > 0 && _price < 2 ** 128 - 1);
        vm.assume(fillAmount < 2 ** 128 - 1);
        vm.assume(receivedAmount < 2 ** 128 - 1);
        vm.assume(orderAmount > 0);

        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(address(paymentToken), orderAmount);
        uint256 fees = flatFee + percentageFee;
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderBridge.Order memory order = IOrderBridge.Order({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderBridge.OrderType.LIMIT,
            assetTokenQuantity: 0,
            paymentTokenQuantity: orderAmount,
            price: _price,
            tif: IOrderBridge.TIF.GTC,
            fee: fees
        });

        bytes32 orderId = issuer.getOrderId(order, salt);

        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), quantityIn);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, salt, fillAmount, receivedAmount);
        } else {
            if (fillAmount > PrbMath.mulDiv18(receivedAmount, order.price)) {
                vm.expectRevert(LimitBuyIssuer.OrderFillBelowLimitPrice.selector);
                vm.prank(operator);
                issuer.fillOrder(order, salt, fillAmount, receivedAmount);
            } else {
                // balances before
                uint256 userAssetBefore = token.balanceOf(user);
                uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
                uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
                vm.assume(fillAmount < orderAmount);
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
                }
            }
        }
    }
}
