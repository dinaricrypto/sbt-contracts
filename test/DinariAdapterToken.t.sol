// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "./utils/mocks/GetMockDShareFactory.sol";
import {DShare} from "../src/DShare.sol";
import {WrappedDShare} from "../src/WrappedDShare.sol";
import "../src/orders/OrderProcessor.sol";
import {DinariAdapterToken, ComponentToken} from "../src/plume-nest/DinariAdapterToken.sol";
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

    function getDummyOrder(bool sell) internal view returns (IOrderProcessor.Order memory) {
        return IOrderProcessor.Order({
            requestTimestamp: uint64(block.timestamp),
            recipient: user,
            assetToken: address(token),
            paymentToken: address(usd),
            sell: sell,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: sell ? 100 ether : 0,
            paymentTokenQuantity: sell ? 0 : 100 * 10 ** usd.decimals(),
            price: 0,
            tif: IOrderProcessor.TIF.GTC
        });
    }

    function testConvertToSharesTooSmallReverts(uint256 amount) public {
        (uint256 flatFee,) = issuer.getStandardFees(false, address(usd));
        vm.assume(amount <= flatFee);

        // Fail if amount too small
        vm.expectRevert(DinariAdapterToken.AmountTooSmall.selector);
        adapterToken.convertToShares(0);
    }

    function testConvertToSharesNoPriceReverts(uint256 amount) public {
        (uint256 flatFee,) = issuer.getStandardFees(false, address(usd));
        vm.assume(amount > flatFee);

        // Fail if no price
        vm.expectRevert(DinariAdapterToken.InvalidPrice.selector);
        adapterToken.convertToShares(amount);
    }

    function testConvertToSharesStalePriceReverts(uint256 amount) public {
        (uint256 flatFee,) = issuer.getStandardFees(false, address(usd));
        vm.assume(amount > flatFee);

        uint64 priceTime = uint64(block.timestamp);

        // Place order to set price
        uint256 price = 10;
        IOrderProcessor.Order memory order = getDummyOrder(false);
        vm.prank(admin);
        usd.mint(address(this), order.paymentTokenQuantity * 2);
        usd.approve(address(issuer), order.paymentTokenQuantity * 2);
        uint256 id = issuer.createOrderStandardFees(order);
        vm.prank(operator);
        issuer.fillOrder(order, order.paymentTokenQuantity, order.paymentTokenQuantity / price, 0);

        vm.warp(block.timestamp + 1 days + 1);

        vm.expectRevert(
            abi.encodeWithSelector(DinariAdapterToken.StalePrice.selector, uint64(block.timestamp), priceTime)
        );
        adapterToken.convertToShares(amount);
    }

    function testConvertToShares(uint256 amount) public {
        (uint256 flatFee,) = issuer.getStandardFees(false, address(usd));
        vm.assume(amount > flatFee);

        // Place order to set price
        uint256 price = 10;
        IOrderProcessor.Order memory order = getDummyOrder(false);
        vm.prank(admin);
        usd.mint(address(this), order.paymentTokenQuantity * 2);
        usd.approve(address(issuer), order.paymentTokenQuantity * 2);
        uint256 id = issuer.createOrderStandardFees(order);
        vm.prank(operator);
        issuer.fillOrder(order, order.paymentTokenQuantity, order.paymentTokenQuantity / price, 0);

        // Convert to shares
        uint256 shares = adapterToken.convertToShares(amount);
        assertLe(shares, amount / price);
    }

    function testConvertToAssetsNoPriceReverts(uint256 shares) public {
        vm.assume(shares > 0);

        // Fail if no price
        vm.expectRevert(DinariAdapterToken.InvalidPrice.selector);
        adapterToken.convertToAssets(shares);
    }

    function testConvertToAssetsStalePriceReverts(uint256 shares) public {
        vm.assume(shares > 0);
        uint256 price = 10;
        vm.assume(!NumberUtils.mulCheckOverflow(shares, price));

        uint64 priceTime = uint64(block.timestamp);

        // Place order to set price
        IOrderProcessor.Order memory order = getDummyOrder(true);
        vm.prank(admin);
        token.mint(address(this), order.assetTokenQuantity);
        token.approve(address(issuer), order.assetTokenQuantity);
        uint256 id = issuer.createOrderStandardFees(order);
        uint256 fillAmount = order.assetTokenQuantity * price;
        vm.prank(admin);
        usd.mint(operator, fillAmount);
        vm.startPrank(operator);
        usd.approve(address(issuer), fillAmount);
        issuer.fillOrder(order, order.assetTokenQuantity, order.assetTokenQuantity * price, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);

        vm.expectRevert(
            abi.encodeWithSelector(DinariAdapterToken.StalePrice.selector, uint64(block.timestamp), priceTime)
        );
        adapterToken.convertToAssets(shares);
    }

    function testConvertToAssets(uint256 shares) public {
        vm.assume(shares > 0);
        uint256 price = 10;
        vm.assume(!NumberUtils.mulCheckOverflow(shares, price));

        // Place order to set price
        IOrderProcessor.Order memory order = getDummyOrder(true);
        vm.prank(admin);
        token.mint(address(this), order.assetTokenQuantity);
        token.approve(address(issuer), order.assetTokenQuantity);
        uint256 id = issuer.createOrderStandardFees(order);
        uint256 fillAmount = order.assetTokenQuantity * price;
        vm.prank(admin);
        usd.mint(operator, fillAmount);
        vm.startPrank(operator);
        usd.approve(address(issuer), fillAmount);
        issuer.fillOrder(order, order.assetTokenQuantity, order.assetTokenQuantity * price, 0);
        vm.stopPrank();

        // Convert to assets
        uint256 assets = adapterToken.convertToAssets(shares);
        assertLe(assets, shares * price);
    }

    function testRequestDepositFillProcessRequestRedeemFillProcess(uint128 amount) public {
        vm.assume(amount > 0.2e8);

        vm.prank(admin);
        usd.mint(nest, amount);

        // request must come from nest
        vm.expectRevert(abi.encodeWithSelector(ComponentToken.Unauthorized.selector, admin, nest));
        vm.prank(admin);
        uint256 orderId = adapterToken.requestDeposit(amount, nest, nest);

        // submit request
        vm.prank(nest);
        usd.approve(address(adapterToken), amount);
        vm.prank(nest);
        orderId = adapterToken.requestDeposit(amount, nest, nest);
        assertEq(adapterToken.balanceOf(nest), 0);
        assertEq(adapterToken.totalSupply(), 0);
        assertEq(usd.balanceOf(address(adapterToken)), 0);
        assertEq(token.balanceOf(address(adapterToken)), 0);
        assertGe(adapterToken.pendingDepositRequest(0, nest), amount - 1);
        assertEq(adapterToken.claimableDepositRequest(0, nest), 0);
        uint256 nextOrder = adapterToken.getNextSubmittedOrder();
        assertEq(nextOrder, orderId);
        assertEq(uint256(issuer.getOrderStatus(orderId)), 1);
        (bool sell, uint256 orderAmount, uint256 fees) = adapterToken.getSubmittedOrderInfo(orderId);
        assertEq(sell, false);

        // process orders does nothing if order not filled
        adapterToken.processSubmittedOrders();
        nextOrder = adapterToken.getNextSubmittedOrder();
        assertEq(nextOrder, orderId);

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
        // fetching order should fail - no more orders
        vm.expectRevert(DinariAdapterToken.NoOutstandingOrders.selector);
        adapterToken.getNextSubmittedOrder();
        assertEq(adapterToken.totalSupply(), 0);
        assertEq(adapterToken.pendingDepositRequest(0, nest), 0);
        uint256 claimableDeposit = adapterToken.claimableDepositRequest(0, nest);
        assertGe(adapterToken.claimableDepositRequest(0, nest), amount - 1);

        // deposit must come from nest
        vm.expectRevert(abi.encodeWithSelector(ComponentToken.Unauthorized.selector, admin, nest));
        vm.prank(admin);
        adapterToken.deposit(orderAmount + 1, nest, nest);

        // deposit must not be too large
        vm.expectRevert(
            abi.encodeWithSelector(ComponentToken.InvalidDepositAmount.selector, claimableDeposit + 1, claimableDeposit)
        );
        vm.prank(nest);
        adapterToken.deposit(claimableDeposit + 1, nest, nest);

        // finalize deposit
        vm.prank(nest);
        adapterToken.deposit(claimableDeposit, nest, nest);
        uint256 shares = adapterToken.balanceOf(nest);
        assertEq(adapterToken.totalSupply(), shares);
        assertEq(shares, wToken.balanceOf(address(adapterToken)));
        assertEq(token.balanceOf(address(adapterToken)), 0);
        assertEq(usd.balanceOf(address(adapterToken)), 0);
        assertEq(adapterToken.pendingDepositRequest(0, nest), 0);
        assertEq(adapterToken.claimableDepositRequest(0, nest), 0);

        // request must come from nest
        vm.expectRevert(abi.encodeWithSelector(ComponentToken.Unauthorized.selector, admin, nest));
        vm.prank(admin);
        orderId = adapterToken.requestRedeem(shares, nest, nest);

        // submit request
        vm.prank(nest);
        orderId = adapterToken.requestRedeem(shares, nest, nest);
        assertEq(adapterToken.balanceOf(nest), 0);
        nextOrder = adapterToken.getNextSubmittedOrder();
        assertEq(nextOrder, orderId);
        assertEq(uint256(issuer.getOrderStatus(orderId)), 1);
        assertEq(adapterToken.pendingRedeemRequest(0, nest), shares);
        assertEq(adapterToken.claimableRedeemRequest(0, nest), 0);

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
        // fetching order should fail - no more orders
        vm.expectRevert(DinariAdapterToken.NoOutstandingOrders.selector);
        adapterToken.getNextSubmittedOrder();
        assertEq(adapterToken.pendingRedeemRequest(0, nest), 0);
        assertEq(adapterToken.claimableRedeemRequest(0, nest), shares);

        // redeem must come from nest
        vm.expectRevert(abi.encodeWithSelector(ComponentToken.Unauthorized.selector, admin, nest));
        vm.prank(admin);
        adapterToken.redeem(shares, nest, nest);

        // finalize redeem
        vm.prank(nest);
        adapterToken.redeem(shares, nest, nest);
        assertEq(token.balanceOf(address(adapterToken)), 0);
        assertEq(usd.balanceOf(address(adapterToken)), 0);
        assertEq(adapterToken.pendingRedeemRequest(0, nest), 0);
        assertEq(adapterToken.claimableRedeemRequest(0, nest), 0);
    }

    function testRequestDepositFillProcessNextRequestRedeemFillProcess(uint128 amount) public {
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

        // process next order reverts if order not filled
        vm.expectRevert(DinariAdapterToken.OrderStillActive.selector);
        adapterToken.processNextSubmittedOrder();
        nextOrder = adapterToken.getNextSubmittedOrder();
        assertEq(nextOrder, orderId);

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
        adapterToken.processNextSubmittedOrder();
        // fetching order should fail - no more orders
        vm.expectRevert(DinariAdapterToken.NoOutstandingOrders.selector);
        adapterToken.getNextSubmittedOrder();

        // finalize deposit
        uint256 claimableDeposit = adapterToken.claimableDepositRequest(0, nest);
        vm.prank(nest);
        adapterToken.deposit(claimableDeposit, nest, nest);
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
        adapterToken.processNextSubmittedOrder();

        // finalize redeem
        vm.prank(nest);
        adapterToken.redeem(shares, nest, nest);
        assertEq(token.balanceOf(address(adapterToken)), 0);
        assertEq(usd.balanceOf(address(adapterToken)), 0);
    }

    function testRequestDepositCancelProcess(uint128 amount) public {
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
        (bool sell, uint256 orderAmount,) = adapterToken.getSubmittedOrderInfo(orderId);
        assertEq(sell, false);
        assertGe(adapterToken.pendingDepositRequest(0, nest), amount - 1);
        assertEq(adapterToken.claimableDepositRequest(0, nest), 0);

        // cancel order
        vm.prank(operator);
        usd.approve(address(issuer), orderAmount);
        vm.prank(operator);
        issuer.cancelOrder(
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
            ""
        );
        assertEq(token.balanceOf(address(adapterToken)), 0);
        assertGe(usd.balanceOf(address(adapterToken)), amount - 1);
        assertEq(uint256(issuer.getOrderStatus(orderId)), 3);
        nextOrder = adapterToken.getNextSubmittedOrder();
        assertEq(nextOrder, orderId);
        assertGe(adapterToken.pendingDepositRequest(0, nest), amount - 1);
        assertEq(adapterToken.claimableDepositRequest(0, nest), 0);

        // update adapter for order
        adapterToken.processSubmittedOrders();
        // fetching order should fail - no more orders
        vm.expectRevert(DinariAdapterToken.NoOutstandingOrders.selector);
        adapterToken.getNextSubmittedOrder();
        assertEq(adapterToken.pendingDepositRequest(0, nest), 0);
        assertEq(adapterToken.claimableDepositRequest(0, nest), 0);
    }
}
