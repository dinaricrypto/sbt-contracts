// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {MockToken} from "../utils/mocks/MockToken.sol";
import "../utils/mocks/MockDShareFactory.sol";
import {OrderProcessor} from "../../src/orders/OrderProcessor.sol";
import {OrderProcessor, IOrderProcessor} from "../../src/orders/OrderProcessor.sol";
import {TransferRestrictor} from "../../src/TransferRestrictor.sol";
import {TokenLockCheck, ITokenLockCheck} from "../../src/TokenLockCheck.sol";
import {NumberUtils} from "../../src/common/NumberUtils.sol";
import {FeeLib} from "../../src/common/FeeLib.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Vault} from "../../src/orders/Vault.sol";
import {FulfillmentRouter} from "../../src/orders/FulfillmentRouter.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract FulfillmentRouterTest is Test {
    event OrderFill(
        uint256 indexed id, address indexed recipient, uint256 fillAmount, uint256 receivedAmount, uint256 feesPaid
    );
    event OrderFulfilled(uint256 indexed id, address indexed recipient);
    event OrderCancelled(uint256 indexed id, address indexed recipient, string reason);

    DShare token;
    OrderProcessor issuer;
    MockToken paymentToken;
    TokenLockCheck tokenLockCheck;
    TransferRestrictor restrictor;
    Vault vault;
    FulfillmentRouter router;

    uint256 userPrivateKey;
    uint256 adminPrivateKey;
    address user;
    address admin;

    address constant operator = address(3);
    address constant treasury = address(4);

    uint256 dummyOrderFees;
    IOrderProcessor.Order dummyOrder;

    function setUp() public {
        userPrivateKey = 0x01;
        adminPrivateKey = 0x02;
        user = vm.addr(userPrivateKey);
        admin = vm.addr(adminPrivateKey);

        vm.startPrank(admin);
        MockDShareFactory tokenFactory = new MockDShareFactory();
        token = tokenFactory.deploy("Dinari Token", "dTKN");
        paymentToken = new MockToken("Money", "$");

        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(0));
        tokenLockCheck.setAsDShare(address(token));

        OrderProcessor issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl), abi.encodeCall(OrderProcessor.initialize, (admin, treasury, tokenLockCheck))
                )
            )
        );
        vault = new Vault(admin);
        router = new FulfillmentRouter();

        token.grantRole(token.MINTER_ROLE(), admin);
        token.grantRole(token.MINTER_ROLE(), address(issuer));
        token.grantRole(token.BURNER_ROLE(), address(issuer));

        OrderProcessor.FeeRates memory defaultFees = OrderProcessor.FeeRates({
            perOrderFeeBuy: 1 ether,
            percentageFeeRateBuy: 5_000,
            perOrderFeeSell: 1 ether,
            percentageFeeRateSell: 5_000
        });
        issuer.setDefaultFees(address(paymentToken), defaultFees);
        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), address(router));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
        issuer.setMaxOrderDecimals(address(token), int8(token.decimals()));

        vault.grantRole(vault.AUTHORIZED_OPERATOR_ROLE(), address(router));

        vm.stopPrank();

        dummyOrder = IOrderProcessor.Order({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 100 ether,
            price: 0,
            tif: IOrderProcessor.TIF.GTC,
            splitAmount: 0,
            splitRecipient: address(0)
        });
    }

    function testFillOrderRevertsUnauthorized() public {
        vm.expectRevert(FulfillmentRouter.Unauthorized.selector);
        vm.prank(admin);
        router.fillOrder(address(issuer), address(vault), 0, dummyOrder, 0, 0);
    }

    function testFillBuyOrder(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount) public {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount > 0);
        vm.assume(fillAmount <= orderAmount);
        uint256 fees;
        {
            (uint256 flatFee, uint24 percentageFeeRate) = issuer.getFeeRatesForOrder(user, false, address(paymentToken));
            fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, orderAmount);
            vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        }
        uint256 quantityIn = orderAmount + fees;

        IOrderProcessor.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;

        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        vm.prank(user);
        uint256 id = issuer.requestOrder(order);

        vm.expectEmit(true, true, true, false);
        emit OrderFill(id, order.recipient, fillAmount, receivedAmount, 0);
        vm.prank(operator);
        router.fillOrder(address(issuer), address(vault), id, order, fillAmount, receivedAmount);
    }

    function testFillSellOrder(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount) public {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount > 0);
        vm.assume(fillAmount <= orderAmount);

        IOrderProcessor.Order memory order = dummyOrder;
        order.sell = true;
        order.paymentTokenQuantity = 0;
        order.assetTokenQuantity = orderAmount;

        vm.prank(admin);
        token.mint(user, orderAmount);
        vm.prank(user);
        token.approve(address(issuer), orderAmount);

        vm.prank(user);
        uint256 id = issuer.requestOrder(order);

        vm.prank(admin);
        paymentToken.mint(address(vault), receivedAmount);

        vm.expectEmit(true, true, true, false);
        emit OrderFill(id, order.recipient, fillAmount, receivedAmount, 0);
        vm.prank(operator);
        router.fillOrder(address(issuer), address(vault), id, order, fillAmount, receivedAmount);
    }
}
