// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "../src/issuer/LimitBuyOrder.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";

contract LimitBuyOrderTest is Test {
    event OrderFill(bytes32 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount);

    BridgedERC20 token;
    OrderFees orderFees;
    LimitBuyOrder issuer;
    MockERC20 paymentToken;

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

        orderFees = new OrderFees(address(this), 1 ether, 0.005 ether);

        LimitBuyOrder issuerImpl = new LimitBuyOrder();
        issuer = LimitBuyOrder(
            address(
                new ERC1967Proxy(address(issuerImpl), abi.encodeCall(issuerImpl.initialize, (address(this), treasury, orderFees)))
            )
        );

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
    }

    function testRequestOrderLimit() public {
        dummyOrder = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: 100 ether,
            price: 0
        });
        paymentToken.mint(user, dummyOrder.quantityIn);
        vm.startPrank(user);
        paymentToken.increaseAllowance(address(issuer), dummyOrder.quantityIn);
        vm.expectRevert(LimitBuyOrder.LimitPriceNotSet.selector);
        issuer.requestOrder(dummyOrder, salt);
        dummyOrder.price = 1 ether;
        issuer.requestOrder(dummyOrder, salt);
        vm.stopPrank();
    }

    function testFillOrderLimit() public {
        uint256 orderAmount = 1000 ether;
        uint256 fillAmount = 500 ether;
        uint256 receivedAmount = 1; // Significantly lower than fillAmount * price to trigger the error

        OrderProcessor.OrderRequest memory order = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: orderAmount,
            price: 1 ether
        });

        (uint256 flatFee, uint256 percentageFee) = issuer.getFeesForOrder(order.paymentToken, order.quantityIn);
        uint256 fees = flatFee + percentageFee;
        vm.assume(fees < orderAmount);

        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);

        paymentToken.mint(user, orderAmount);
        vm.prank(user);
        paymentToken.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        vm.expectRevert(LimitBuyOrder.OrderFillBelowLimitPrice.selector); // Expecting a revert with this reason

        vm.prank(operator);
        issuer.fillOrder(order, salt, fillAmount, receivedAmount);

        receivedAmount = 400 ether;
        // Balances before
        uint256 userAssetBefore = token.balanceOf(user);
        uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
        uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);

        vm.expectEmit(true, true, true, true);
        emit OrderFill(orderId, user, fillAmount, receivedAmount);

        vm.prank(operator);
        issuer.fillOrder(order, salt, fillAmount, receivedAmount);

        assertEq(issuer.getRemainingOrder(orderId), orderAmount - fees - fillAmount);
        assertEq(issuer.getTotalReceived(orderId), receivedAmount);

        // Balances after
        assertEq(token.balanceOf(address(user)), userAssetBefore + receivedAmount);
        assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore - fillAmount);
        assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore + fillAmount);
    }
}