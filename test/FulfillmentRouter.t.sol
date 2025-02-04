// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";
import "./utils/mocks/GetMockDShareFactory.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {OrderProcessor, IOrderProcessor} from "../src/orders/OrderProcessor.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {NumberUtils} from "../src/common/NumberUtils.sol";
import {FeeLib} from "../src/common/FeeLib.sol";
import {mulDiv} from "prb-math/Common.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Vault} from "../src/orders/Vault.sol";
import {FulfillmentRouter} from "../src/orders/FulfillmentRouter.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract FulfillmentRouterTest is Test {
    using GetMockDShareFactory for DShareFactory;

    event OrderFill(
        uint256 indexed id,
        address indexed paymentToken,
        address indexed assetToken,
        address requester,
        uint256 assetAmount,
        uint256 paymentAmount,
        uint256 feesPaid,
        bool sell
    );
    event OrderFulfilled(uint256 indexed id, address indexed recipient);
    event OrderCancelled(uint256 indexed id, address indexed recipient, string reason);

    DShare token;
    OrderProcessor issuer;
    MockToken paymentToken;
    TransferRestrictor restrictor;
    Vault vault;
    FulfillmentRouter router;

    uint256 userPrivateKey;
    uint256 adminPrivateKey;
    uint256 upgraderPrivateKey;
    address user;
    address admin;
    address upgrader;

    address constant operator = address(3);
    address constant treasury = address(4);

    uint256 dummyOrderFees;
    IOrderProcessor.Order dummyOrder;

    function setUp() public {
        userPrivateKey = 0x01;
        adminPrivateKey = 0x02;
        upgraderPrivateKey = 0x03;
        user = vm.addr(userPrivateKey);
        admin = vm.addr(adminPrivateKey);
        upgrader = vm.addr(upgraderPrivateKey);

        vm.startPrank(admin);
        (DShareFactory tokenFactory,,) = GetMockDShareFactory.getMockDShareFactory(admin);
        token = tokenFactory.deployDShare(admin, "Dinari Token", "dTKN");
        paymentToken = new MockToken("Money", "$");

        Vault vaultImpl = new Vault();
        vault =
            Vault(address(new ERC1967Proxy(address(vaultImpl), abi.encodeCall(Vault.initialize, (admin, upgrader)))));
        OrderProcessor issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl),
                    abi.encodeCall(OrderProcessor.initialize, (admin, upgrader, treasury, address(vault), tokenFactory))
                )
            )
        );
        // router = new FulfillmentRouter(admin);
        FulfillmentRouter routerImpl = new FulfillmentRouter();
        router = FulfillmentRouter(
            address(
                new ERC1967Proxy(address(routerImpl), abi.encodeCall(FulfillmentRouter.initialize, (admin, upgrader)))
            )
        );

        token.grantRole(token.MINTER_ROLE(), admin);
        token.grantRole(token.MINTER_ROLE(), address(issuer));
        token.grantRole(token.BURNER_ROLE(), address(issuer));

        issuer.setPaymentToken(address(paymentToken), paymentToken.isBlacklisted.selector, 1e8, 5_000, 1e8, 5_000);
        issuer.setOperator(address(router), true);

        vault.grantRole(vault.OPERATOR_ROLE(), address(router));
        router.grantRole(router.OPERATOR_ROLE(), operator);

        vm.stopPrank();

        dummyOrder = IOrderProcessor.Order({
            requestTimestamp: uint64(block.timestamp),
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 100 ether,
            price: 0,
            tif: IOrderProcessor.TIF.GTC
        });
    }

    function getDummyOrder(bool sell) internal view returns (IOrderProcessor.Order memory) {
        return IOrderProcessor.Order({
            requestTimestamp: uint64(block.timestamp),
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: sell,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: sell ? 100 ether : 0,
            paymentTokenQuantity: sell ? 0 : 100 ether,
            price: 0,
            tif: IOrderProcessor.TIF.GTC
        });
    }

    function testFillOrderRevertsUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, admin, router.OPERATOR_ROLE()
            )
        );
        vm.prank(admin);
        router.fillOrder(address(issuer), address(vault), dummyOrder, 0, 0, 0);
    }

    function testFillBuyOrderReverts() public {
        vm.expectRevert(FulfillmentRouter.BuyFillsNotSupported.selector);
        vm.prank(operator);
        router.fillOrder(address(issuer), address(vault), dummyOrder, 0, 0, 0);
    }

    function testFillSellOrder(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount, uint256 fees) public {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount > 0);
        vm.assume(fillAmount <= orderAmount);
        vm.assume(fees <= receivedAmount);

        IOrderProcessor.Order memory order = dummyOrder;
        order.sell = true;
        order.paymentTokenQuantity = 0;
        order.assetTokenQuantity = orderAmount;

        vm.prank(admin);
        token.mint(user, orderAmount);
        vm.prank(user);
        token.approve(address(issuer), orderAmount);

        vm.prank(user);
        uint256 id = issuer.createOrderStandardFees(order);

        vm.prank(admin);
        paymentToken.mint(address(vault), receivedAmount);

        vm.expectEmit(true, true, true, false);
        emit OrderFill(id, order.paymentToken, order.assetToken, order.recipient, fillAmount, receivedAmount, 0, true);
        vm.prank(operator);
        router.fillOrder(address(issuer), address(vault), order, fillAmount, receivedAmount, fees);
    }

    function testCancelOrder(uint256 orderAmount, uint256 fillAmount) public {
        vm.prank(admin);
        issuer.setOperator(operator, true);
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount < orderAmount);
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(paymentToken));
        uint256 fees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderProcessor.Order memory order = getDummyOrder(false);
        order.paymentTokenQuantity = orderAmount;

        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);
        vm.prank(user);
        uint256 id = issuer.createOrderStandardFees(order);

        uint256 feesEarned = 0;
        if (fillAmount > 0) {
            feesEarned = flatFee + mulDiv(fees - flatFee, fillAmount, order.paymentTokenQuantity);
            vm.prank(operator);
            issuer.fillOrder(order, fillAmount, 100, feesEarned);
        }

        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(id, order.recipient, "cancel");
        vm.prank(operator);
        router.cancelBuyOrder(address(issuer), order, address(vault), id, "cancel");
        assertEq(paymentToken.balanceOf(address(issuer)), 0);
        assertEq(paymentToken.balanceOf(treasury), feesEarned);
        // balances after
        if (fillAmount > 0) {
            assertEq(paymentToken.balanceOf(address(user)), quantityIn - fillAmount - feesEarned);
        } else {
            assertEq(paymentToken.balanceOf(address(user)), quantityIn);
        }
        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.CANCELLED));
    }

    function testCancelOrderRevertSell(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount, uint256 fees)
        public
    {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount > 0);
        vm.assume(fillAmount <= orderAmount);
        vm.assume(fees <= receivedAmount);

        dummyOrder.sell = true;
        dummyOrder.assetTokenQuantity = orderAmount;
        dummyOrder.paymentTokenQuantity = 0;

        vm.prank(admin);
        token.mint(user, orderAmount);
        vm.prank(user);
        token.approve(address(issuer), orderAmount);

        vm.prank(user);
        uint256 id = issuer.createOrderStandardFees(dummyOrder);

        vm.prank(admin);
        paymentToken.mint(address(vault), receivedAmount);

        vm.expectEmit(true, true, true, false);
        emit OrderFill(
            id,
            dummyOrder.paymentToken,
            dummyOrder.assetToken,
            dummyOrder.recipient,
            fillAmount,
            receivedAmount,
            0,
            true
        );
        vm.prank(operator);
        router.fillOrder(address(issuer), address(vault), dummyOrder, fillAmount, receivedAmount, fees);

        vm.expectRevert(FulfillmentRouter.OnlyForBuyOrders.selector);
        vm.prank(operator);
        router.cancelBuyOrder(address(issuer), dummyOrder, address(vault), id, "cancel");
    }
}
