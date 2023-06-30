// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "../src/issuer/LimitSellOrder.sol";
import "../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";

contract LimitSellOrderTest is Test {
    event OrderFill(bytes32 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount);

    BridgedERC20 token;
    OrderFees orderFees;
    LimitSellOrder issuer;
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

        LimitSellOrder issuerImpl = new LimitSellOrder();
        issuer = LimitSellOrder(
            address(
                new ERC1967Proxy(address(issuerImpl), abi.encodeCall(issuerImpl.initialize, (address(this), treasury, orderFees)))
            )
        );

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.BURNER_ROLE(), address(issuer));

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
        token.mint(user, dummyOrder.quantityIn);
        vm.startPrank(user);
        token.increaseAllowance(address(issuer), dummyOrder.quantityIn);
        vm.expectRevert(LimitSellOrder.LimitPriceNotSet.selector);
        issuer.requestOrder(dummyOrder, salt);
        dummyOrder.price = 1 ether;
        issuer.requestOrder(dummyOrder, salt);
        vm.stopPrank();
    }

    function testFillSellOrderLimit() public {
        uint256 orderAmount = 100 ether;
        uint256 fillAmount = 1;
        uint256 receivedAmount = 50 ether;

        OrderProcessor.OrderRequest memory order = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: orderAmount,
            price: 1 ether
        });

        bytes32 orderId = issuer.getOrderIdFromOrderRequest(order, salt);

        token.mint(user, orderAmount);
        vm.prank(user);
        token.increaseAllowance(address(issuer), orderAmount);

        vm.prank(user);
        issuer.requestOrder(order, salt);

        paymentToken.mint(operator, receivedAmount); // Mint paymentTokens to operator to ensure they have enough
        vm.prank(operator);
        paymentToken.increaseAllowance(address(issuer), receivedAmount);

        vm.expectRevert(LimitSellOrder.OrderFillAboveLimitPrice.selector);
        vm.prank(operator);
        issuer.fillOrder(order, salt, fillAmount, receivedAmount);

        fillAmount = 50 ether;

        // Balances before
        uint256 issuerPaymentBefore = paymentToken.balanceOf(address(issuer));
        uint256 issuerAssetBefore = token.balanceOf(address(issuer));
        uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);

        vm.expectEmit(true, true, true, true);
        emit OrderFill(orderId, user, fillAmount, receivedAmount);

        vm.prank(operator);

        issuer.fillOrder(order, salt, fillAmount, receivedAmount);

        assertEq(issuer.getRemainingOrder(orderId), orderAmount - fillAmount);
        assertEq(issuer.getTotalReceived(orderId), receivedAmount);
        // balances after
        assertEq(paymentToken.balanceOf(address(issuer)), issuerPaymentBefore + receivedAmount);
        assertEq(token.balanceOf(address(issuer)), issuerAssetBefore - fillAmount);
        assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore - receivedAmount);
    }
}
