// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OrderProcessor} from "../src/issuer/OrderProcessor.sol";
import "./utils/mocks/MockdShare.sol";
import "../src/issuer/LimitSellProcessor.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import {TokenLockCheck, ITokenLockCheck} from "../src/TokenLockCheck.sol";
import {FeeLib} from "../src/FeeLib.sol";

contract LimitSellProcessorTest is Test {
    event OrderRequested(address indexed recipient, uint256 indexed index, IOrderBridge.Order order);
    event OrderFill(address indexed recipient, uint256 indexed index, uint256 fillAmount, uint256 receivedAmount);

    dShare token;
    OrderFees orderFees;
    TokenLockCheck tokenLockCheck;
    LimitSellProcessor issuer;
    MockToken paymentToken;

    uint256 userPrivateKey;
    address user;

    address constant operator = address(3);
    address constant treasury = address(4);

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockdShare();
        paymentToken = new MockToken();

        orderFees = new OrderFees(address(this), 1 ether, 5_000);

        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(paymentToken));

        issuer = new LimitSellProcessor(address(this), treasury, orderFees, tokenLockCheck);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.BURNER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
    }

    function createOrder(uint256 orderAmount, uint256 price) internal view returns (IOrderBridge.Order memory order) {
        order = IOrderBridge.Order({
            recipient: user,
            index: 0,
            quantityIn: orderAmount,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: true,
            orderType: IOrderBridge.OrderType.LIMIT,
            assetTokenQuantity: orderAmount,
            paymentTokenQuantity: 0,
            price: price,
            tif: IOrderBridge.TIF.GTC
        });
    }

    function testRequestOrderLimit(uint256 orderAmount, uint256 _price) public {
        IOrderBridge.Order memory order = createOrder(orderAmount, _price);

        token.mint(user, orderAmount);
        vm.prank(user);
        token.increaseAllowance(address(issuer), orderAmount);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);
        if (orderAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(user);
            issuer.requestOrder(order);
        } else if (_price == 0) {
            vm.expectRevert(LimitSellProcessor.LimitPriceNotSet.selector);
            vm.prank(user);
            issuer.requestOrder(order);
        } else {
            // balances before
            uint256 userBalanceBefore = token.balanceOf(user);
            uint256 issuerBalanceBefore = token.balanceOf(address(issuer));
            vm.expectEmit(true, true, true, true);
            emit OrderRequested(user, order.index, order);
            vm.prank(user);
            uint256 index = issuer.requestOrder(order);
            assertEq(index, order.index);
            assertTrue(issuer.isOrderActive(id));
            assertEq(issuer.getRemainingOrder(id), orderAmount);
            assertEq(issuer.numOpenOrders(), 1);
            assertEq(token.balanceOf(address(issuer)), orderAmount);
            // balances after
            assertEq(token.balanceOf(user), userBalanceBefore - orderAmount);
            assertEq(token.balanceOf(address(issuer)), issuerBalanceBefore + orderAmount);
        }
    }

    function testFillSellOrderLimit(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount, uint256 _price)
        public
    {
        vm.assume(orderAmount > 0);
        vm.assume(_price > 0 && _price < 2 ** 128 - 1);
        vm.assume(fillAmount < 2 ** 128 - 1);
        vm.assume(receivedAmount < 2 ** 128 - 1);

        IOrderBridge.Order memory order = createOrder(orderAmount, _price);

        token.mint(user, orderAmount);
        vm.prank(user);
        token.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order);

        paymentToken.mint(operator, receivedAmount); // Mint paymentTokens to operator to ensure they have enough
        vm.prank(operator);
        paymentToken.increaseAllowance(address(issuer), receivedAmount);

        bytes32 id = issuer.getOrderId(order.recipient, order.index);
        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        } else if (receivedAmount < PrbMath.mulDiv18(fillAmount, order.price)) {
            vm.expectRevert(LimitSellProcessor.OrderFillAboveLimitPrice.selector);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
        } else {
            // balances before
            uint256 issuerAssetBefore = token.balanceOf(address(issuer));
            uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
            vm.expectEmit(true, true, true, true);
            emit OrderFill(user, order.index, fillAmount, receivedAmount);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, receivedAmount);
            assertEq(issuer.getRemainingOrder(id), orderAmount - fillAmount);
            if (fillAmount == orderAmount) {
                assertEq(issuer.numOpenOrders(), 0);
                assertEq(issuer.getTotalReceived(id), 0);
            } else {
                assertEq(issuer.getTotalReceived(id), receivedAmount);
                // balances after
                // assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore + receivedAmount);
                assertEq(token.balanceOf(address(issuer)), issuerAssetBefore - fillAmount);
                assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore - receivedAmount);
            }
        }
    }
}
