// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import "./utils/mocks/GetMockDShareFactory.sol";
import "../src/orders/OrderProcessor.sol";
import "../src/orders/IOrderProcessor.sol";
import {NumberUtils} from "../src/common/NumberUtils.sol";
import {FeeLib} from "../src/common/FeeLib.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract LimitOrderTest is Test {
    using GetMockDShareFactory for DShareFactory;

    DShareFactory tokenFactory;
    DShare token;
    OrderProcessor issuer;
    MockToken paymentToken;

    uint256 userPrivateKey;
    uint256 adminPrivateKey;
    address user;
    address admin;

    address constant operator = address(3);
    address constant treasury = address(4);
    address constant upgrader = address(5);

    uint256 flatFee;
    uint24 percentageFeeRate;

    function setUp() public {
        userPrivateKey = 0x01;
        adminPrivateKey = 0x02;
        user = vm.addr(userPrivateKey);
        admin = vm.addr(adminPrivateKey);

        vm.startPrank(admin);
        (tokenFactory,,) = GetMockDShareFactory.getMockDShareFactory(admin);
        token = tokenFactory.deployDShare(admin, "Dinari Token", "dTKN");
        paymentToken = new MockToken("Money", "$");

        OrderProcessor issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl),
                    abi.encodeCall(OrderProcessor.initialize, (admin, upgrader, treasury, operator, tokenFactory))
                )
            )
        );

        token.grantRole(token.MINTER_ROLE(), admin);
        token.grantRole(token.MINTER_ROLE(), address(issuer));
        token.grantRole(token.BURNER_ROLE(), address(issuer));

        issuer.setPaymentToken(address(paymentToken), paymentToken.isBlacklisted.selector, 1e8, 5_000, 1e8, 5_000);
        issuer.setOperator(operator, true);

        vm.stopPrank();

        (flatFee, percentageFeeRate) = issuer.getStandardFees(false, address(paymentToken));
    }

    function createLimitOrder(bool sell, uint256 orderAmount, uint256 price)
        internal
        view
        returns (IOrderProcessor.Order memory order)
    {
        order = IOrderProcessor.Order({
            requestTimestamp: uint64(block.timestamp),
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: sell,
            orderType: IOrderProcessor.OrderType.LIMIT,
            assetTokenQuantity: sell ? orderAmount : 0,
            paymentTokenQuantity: sell ? 0 : orderAmount,
            price: price,
            tif: IOrderProcessor.TIF.GTC
        });
    }

    function testRequestLimitOrderNoPriceReverts(uint256 orderAmount) public {
        vm.assume(orderAmount > 0);

        IOrderProcessor.Order memory order = createLimitOrder(false, orderAmount, 0);

        vm.startPrank(admin);
        paymentToken.mint(user, order.paymentTokenQuantity);
        vm.startPrank(user);
        paymentToken.approve(address(issuer), order.paymentTokenQuantity);

        vm.expectRevert(OrderProcessor.LimitPriceNotSet.selector);
        vm.startPrank(user);
        issuer.createOrderStandardFees(order);
    }

    function testFillLimitBuyOrderPriceReverts(
        uint256 orderAmount,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256 _price
    ) public {
        vm.assume(_price > 0);
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount > 0 && fillAmount <= orderAmount);
        vm.assume(!NumberUtils.mulDivCheckOverflow(fillAmount, 1 ether, _price));
        uint256 fees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        vm.assume(receivedAmount < mulDiv(fillAmount, 1 ether, _price));

        IOrderProcessor.Order memory order = createLimitOrder(false, orderAmount, _price);

        vm.prank(admin);
        paymentToken.mint(user, order.paymentTokenQuantity + fees);
        vm.prank(user);
        paymentToken.approve(address(issuer), order.paymentTokenQuantity + fees);

        vm.prank(user);
        issuer.createOrderStandardFees(order);

        vm.expectRevert(OrderProcessor.OrderFillBelowLimitPrice.selector);
        vm.prank(operator);
        issuer.fillOrder(order, fillAmount, receivedAmount, fees);
    }

    function testFillLimitSellOrderPriceReverts(
        uint256 orderAmount,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256 fees,
        uint256 _price
    ) public {
        vm.assume(_price > 0);
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount > 0 && fillAmount <= orderAmount);
        vm.assume(fees <= receivedAmount);
        vm.assume(!NumberUtils.mulDivCheckOverflow(fillAmount, _price, 1 ether));
        vm.assume(receivedAmount < mulDiv18(fillAmount, _price));

        IOrderProcessor.Order memory order = createLimitOrder(true, orderAmount, _price);

        vm.prank(admin);
        token.mint(user, order.assetTokenQuantity);
        vm.prank(user);
        token.approve(address(issuer), order.assetTokenQuantity);

        vm.prank(user);
        issuer.createOrderStandardFees(order);

        vm.expectRevert(OrderProcessor.OrderFillAboveLimitPrice.selector);
        vm.prank(operator);
        issuer.fillOrder(order, fillAmount, receivedAmount, fees);
    }

    function testFillLimitBuyOrder(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount, uint256 _price)
        public
    {
        vm.assume(_price > 0);
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount > 0 && fillAmount <= orderAmount);
        vm.assume(!NumberUtils.mulDivCheckOverflow(fillAmount, 1 ether, _price));
        uint256 fees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        vm.assume(receivedAmount >= mulDiv(fillAmount, 1 ether, _price));

        IOrderProcessor.Order memory order = createLimitOrder(false, orderAmount, _price);

        vm.prank(admin);
        paymentToken.mint(user, order.paymentTokenQuantity + fees);
        vm.prank(user);
        paymentToken.approve(address(issuer), order.paymentTokenQuantity + fees);

        vm.prank(user);
        issuer.createOrderStandardFees(order);

        vm.prank(operator);
        issuer.fillOrder(order, fillAmount, receivedAmount, fees);
        IOrderProcessor.PricePoint memory fillPrice = issuer.latestFillPrice(order.assetToken, order.paymentToken);
        assertEq(fillPrice.price, _price);
    }
}
