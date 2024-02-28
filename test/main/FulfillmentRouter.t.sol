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
        uint256 indexed id,
        address indexed paymentToken,
        address indexed assetToken,
        address requester,
        uint256 paymentAmount,
        uint256 assetAmount,
        uint256 feesPaid,
        bool sell
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

        vault = new Vault(admin);
        OrderProcessor issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl),
                    abi.encodeCall(
                        OrderProcessor.initialize, (admin, treasury, address(vault), tokenLockCheck, address(1))
                    )
                )
            )
        );
        router = new FulfillmentRouter(admin);

        token.grantRole(token.MINTER_ROLE(), admin);
        token.grantRole(token.MINTER_ROLE(), address(issuer));
        token.grantRole(token.BURNER_ROLE(), address(issuer));

        issuer.setFees(address(0), address(paymentToken), 1 ether, 5_000, 1 ether, 5_000);
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), address(router));
        issuer.setMaxOrderDecimals(address(token), int8(token.decimals()));

        vault.grantRole(vault.OPERATOR_ROLE(), address(router));
        router.grantRole(router.OPERATOR_ROLE(), operator);

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
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, admin, router.OPERATOR_ROLE()
            )
        );
        vm.prank(admin);
        router.fillOrder(address(issuer), address(vault), 0, dummyOrder, 0, 0);
    }

    function testFillBuyOrderReverts() public {
        vm.expectRevert(FulfillmentRouter.BuyFillsNotSupported.selector);
        vm.prank(operator);
        router.fillOrder(address(issuer), address(vault), 0, dummyOrder, 0, 0);
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
        emit OrderFill(id, order.paymentToken, order.assetToken, order.recipient, receivedAmount, fillAmount, 0, true);
        vm.prank(operator);
        router.fillOrder(address(issuer), address(vault), id, order, fillAmount, receivedAmount);
    }
}
