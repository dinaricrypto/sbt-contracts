// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "./utils/mocks/GetMockDShareFactory.sol";
import {DShare} from "../src/DShare.sol";
import {WrappedDShare} from "../src/WrappedDShare.sol";
import "../src/orders/OrderProcessor.sol";
import {DinariAdapterToken} from "../src/plume-nest/DinariAdapterToken.sol";
import {
    IAccessControlDefaultAdminRules,
    IAccessControl
} from "openzeppelin-contracts/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PRBMath_MulDiv18_Overflow, PRBMath_MulDiv_Overflow} from "prb-math/Common.sol";
import {NumberUtils} from "../src/common/NumberUtils.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";

contract DinariAdapterTokenTest is Test {
    using GetMockDShareFactory for DShareFactory;

    DShareFactory tokenFactory;
    DShare token;
    WrappedDShare wToken;
    MockToken usd;
    OrderProcessor issuer;
    DinariAdapterToken adapterToken;

    address user = address(2);
    address admin = address(3);
    address nest = address(4);
    address treasury = address(5);
    address operator = address(6);

    function setUp() public {
        vm.startPrank(admin);
        (tokenFactory,,) = GetMockDShareFactory.getMockDShareFactory(admin);
        (address tokenAddress, address wTokenAddress) =
            tokenFactory.createDShare(admin, "Dinari Token", "D", "Wrapped D.d", "D.dw");
        token = DShare(tokenAddress);
        wToken = WrappedDShare(wTokenAddress);
        token.grantRole(token.MINTER_ROLE(), admin);

        usd = new MockToken("USD", "USD");

        OrderProcessor issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl),
                    abi.encodeCall(OrderProcessor.initialize, (admin, treasury, operator, tokenFactory))
                )
            )
        );
        token.grantRole(token.MINTER_ROLE(), address(issuer));
        token.grantRole(token.BURNER_ROLE(), address(issuer));
        issuer.setPaymentToken(address(usd), usd.isBlacklisted.selector, 0.2e8, 5_000, 0.2e8, 5_000);
        issuer.setOperator(operator, true);

        DinariAdapterToken adapterTokenImplementation = new DinariAdapterToken();
        adapterToken = DinariAdapterToken(
            address(
                new ERC1967Proxy(
                    address(adapterTokenImplementation),
                    abi.encodeCall(
                        DinariAdapterToken.initialize,
                        (admin, "Nest D", "nD.dw", address(usd), address(token), address(wToken), nest, address(issuer))
                    )
                )
            )
        );

        vm.stopPrank();
    }

    function testRequestDepositFillProcessRequestRedeemFillProcess(uint128 amount) public {
        vm.assume(amount > 0.2e8);

        vm.prank(admin);
        usd.mint(nest, amount);

        // submit request
        vm.prank(nest);
        usd.approve(address(adapterToken), amount);
        vm.prank(nest);
        uint256 orderId = adapterToken.requestDeposit(amount, nest, nest);
        assertEq(adapterToken.balanceOf(nest), 0);
        assertEq(usd.balanceOf(address(adapterToken)), 0);
        assertEq(token.balanceOf(address(adapterToken)), 0);
        uint256 nextOrder = adapterToken.getNextSubmittedOrder();
        assertEq(nextOrder, orderId);
        assertEq(uint256(issuer.getOrderStatus(orderId)), 1);
        (bool sell, uint256 orderAmount, uint256 fees) = adapterToken.getSubmittedOrderInfo(orderId);
        assertEq(sell, false);

        // fill order
        vm.prank(operator);
        issuer.fillOrder(
            IOrderProcessor.Order(
                uint64(0),
                address(adapterToken),
                address(token),
                address(usd),
                false,
                IOrderProcessor.OrderType.MARKET,
                0,
                orderAmount,
                0,
                IOrderProcessor.TIF.DAY
            ),
            orderAmount,
            orderAmount + 1,
            fees - 1
        );
        assertEq(token.balanceOf(address(adapterToken)), orderAmount + 1);
        assertEq(usd.balanceOf(address(adapterToken)), 1);
        assertEq(uint256(issuer.getOrderStatus(orderId)), 2);
        nextOrder = adapterToken.getNextSubmittedOrder();
        assertEq(nextOrder, orderId);

        // update adapter for order
        adapterToken.processSubmittedOrders();
        vm.expectRevert(DinariAdapterToken.NoOutstandingOrders.selector);
        adapterToken.getNextSubmittedOrder();

        // finalize deposit
        vm.prank(nest);
        adapterToken.deposit(orderAmount + 1, nest, nest);
        uint256 shares = adapterToken.balanceOf(nest);
        assertEq(shares, wToken.balanceOf(address(adapterToken)));
        assertEq(token.balanceOf(address(adapterToken)), 0);
        assertEq(usd.balanceOf(address(adapterToken)), 0);

        // submit request
        vm.prank(nest);
        orderId = adapterToken.requestRedeem(shares, nest, nest);
        assertEq(adapterToken.balanceOf(nest), 0);
        nextOrder = adapterToken.getNextSubmittedOrder();
        assertEq(nextOrder, orderId);
        assertEq(uint256(issuer.getOrderStatus(orderId)), 1);

        // fill order
        vm.prank(admin);
        usd.mint(operator, shares + 1);
        vm.prank(operator);
        usd.approve(address(issuer), shares + 1);
        vm.prank(operator);
        issuer.fillOrder(
            IOrderProcessor.Order(
                uint64(1),
                address(adapterToken),
                address(token),
                address(usd),
                true,
                IOrderProcessor.OrderType.MARKET,
                shares,
                0,
                0,
                IOrderProcessor.TIF.DAY
            ),
            shares,
            shares + 1,
            2
        );
        assertEq(usd.balanceOf(address(adapterToken)), shares - 1);
        assertEq(token.balanceOf(address(adapterToken)), 0);
        assertEq(uint256(issuer.getOrderStatus(orderId)), 2);
        nextOrder = adapterToken.getNextSubmittedOrder();
        assertEq(nextOrder, orderId);

        // update adapter for order
        adapterToken.processSubmittedOrders();
        vm.expectRevert(DinariAdapterToken.NoOutstandingOrders.selector);
        adapterToken.getNextSubmittedOrder();

        // finalize redeem
        vm.prank(nest);
        adapterToken.redeem(shares, nest, nest);
        assertEq(token.balanceOf(address(adapterToken)), 0);
        assertEq(usd.balanceOf(address(adapterToken)), 0);
    }
}
