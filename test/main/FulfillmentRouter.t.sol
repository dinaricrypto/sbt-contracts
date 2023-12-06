// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {MockToken} from "../utils/mocks/MockToken.sol";
import "../utils/mocks/MockdShareFactory.sol";
import {EscrowOrderProcessor} from "../../src/orders/EscrowOrderProcessor.sol";
import {OrderProcessor, IOrderProcessor} from "../../src/orders/OrderProcessor.sol";
import {TransferRestrictor} from "../../src/TransferRestrictor.sol";
import {TokenLockCheck, ITokenLockCheck} from "../../src/TokenLockCheck.sol";
import {NumberUtils} from "../../src/common/NumberUtils.sol";
import {FeeLib} from "../../src/common/FeeLib.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Vault} from "../../src/orders/Vault.sol";
import {FulfillmentRouter} from "../../src/orders/FulfillmentRouter.sol";

contract FulfillmentRouterTest is Test {
    event OrderFill(
        address indexed recipient, uint256 indexed index, uint256 fillAmount, uint256 receivedAmount, uint256 feesPaid
    );
    event OrderFulfilled(address indexed recipient, uint256 indexed index);
    event OrderCancelled(address indexed recipient, uint256 indexed index, string reason);

    dShare token;
    EscrowOrderProcessor issuer;
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
        MockdShareFactory tokenFactory = new MockdShareFactory();
        token = tokenFactory.deploy("Dinari Token", "dTKN");
        paymentToken = new MockToken("Money", "$");

        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(0));
        tokenLockCheck.setAsDShare(address(token));

        issuer = new EscrowOrderProcessor(
            admin,
            treasury,
            OrderProcessor.FeeRates({
                perOrderFeeBuy: 1 ether,
                percentageFeeRateBuy: 5_000,
                perOrderFeeSell: 1 ether,
                percentageFeeRateSell: 5_000
            }),
            tokenLockCheck
        );
        vault = new Vault(admin);
        router = new FulfillmentRouter();

        token.grantRole(token.MINTER_ROLE(), admin);
        token.grantRole(token.MINTER_ROLE(), address(issuer));
        token.grantRole(token.BURNER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));

        issuer.grantRole(issuer.OPERATOR_ROLE(), address(router));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
        issuer.grantRole(issuer.SELL_ASSET_ROLE(), address(token));
        issuer.grantRole(issuer.BUY_ASSET_ROLE(), address(token));

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
            tif: IOrderProcessor.TIF.GTC
        });
    }

    function testFillOrderRevertsUnauthorized() public {
        vm.expectRevert(FulfillmentRouter.Unauthorized.selector);
        vm.prank(admin);
        router.fillOrder(address(issuer), address(vault), dummyOrder, 0, 0, 0);
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
        uint256 index = issuer.requestOrder(order);

        vm.expectEmit(true, true, true, false);
        emit OrderFill(order.recipient, index, fillAmount, receivedAmount, 0);
        vm.prank(operator);
        router.fillOrder(address(issuer), address(vault), order, index, fillAmount, receivedAmount);
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
        uint256 index = issuer.requestOrder(order);

        vm.prank(admin);
        paymentToken.mint(address(vault), receivedAmount);

        vm.expectEmit(true, true, true, false);
        emit OrderFill(order.recipient, index, fillAmount, receivedAmount, 0);
        vm.prank(operator);
        router.fillOrder(address(issuer), address(vault), order, index, fillAmount, receivedAmount);
    }
}
