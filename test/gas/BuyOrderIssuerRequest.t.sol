// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockToken} from "../utils/mocks/MockToken.sol";
import "../utils/mocks/GetMockDShareFactory.sol";
import "../utils/SigUtils.sol";
import "../../src/orders/OrderProcessor.sol";
import "../../src/orders/IOrderProcessor.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import {NumberUtils} from "../../src/common/NumberUtils.sol";
import {FeeLib} from "../../src/common/FeeLib.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BuyProcessorRequestTest is Test {
    // More calls to permit and multicall for gas profiling
    using GetMockDShareFactory for DShareFactory;

    DShareFactory tokenFactory;
    DShare token;
    OrderProcessor issuer;
    MockToken paymentToken;
    SigUtils sigUtils;

    uint256 userPrivateKey;
    uint256 adminPrivateKey;
    address user;
    address admin;

    address constant operator = address(3);
    address constant treasury = address(4);
    address constant upgrader = address(5);

    uint8 v;
    bytes32 r;
    bytes32 s;

    uint256 flatFee;
    uint24 percentageFeeRate;
    IOrderProcessor.Order order;
    bytes[] calls;

    function setUp() public {
        userPrivateKey = 0x01;
        adminPrivateKey = 0x02;
        user = vm.addr(userPrivateKey);
        admin = vm.addr(adminPrivateKey);

        vm.startPrank(admin);
        (tokenFactory,,) = GetMockDShareFactory.getMockDShareFactory(admin);
        token = tokenFactory.deployDShare(admin, "Dinari Token", "dTKN");
        paymentToken = new MockToken("Money", "$");
        sigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());

        OrderProcessor issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl),
                    abi.encodeCall(issuerImpl.initialize, (admin, upgrader, treasury, operator, tokenFactory))
                )
            )
        );

        token.grantRole(token.MINTER_ROLE(), admin);
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        issuer.setPaymentToken(address(paymentToken), paymentToken.isBlacklisted.selector, 1e8, 5_000, 1e8, 5_000);
        issuer.setOperator(operator, true);

        paymentToken.mint(user, type(uint256).max);

        vm.stopPrank();

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: user,
            spender: address(issuer),
            value: type(uint256).max,
            nonce: 0,
            deadline: block.timestamp + 30 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (v, r, s) = vm.sign(userPrivateKey, digest);

        (flatFee, percentageFeeRate) = issuer.getStandardFees(false, address(paymentToken));
        order = IOrderProcessor.Order({
            requestTimestamp: uint64(block.timestamp),
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 1 ether,
            price: 0,
            tif: IOrderProcessor.TIF.GTC
        });

        calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            issuer.selfPermit.selector,
            address(paymentToken),
            user,
            type(uint256).max,
            block.timestamp + 30 days,
            v,
            r,
            s
        );
        calls[1] = abi.encodeWithSelector(issuer.createOrderStandardFees.selector, order, bytes32("0x01"));
    }

    function testSelfPermit() public {
        vm.prank(user);
        issuer.selfPermit(address(paymentToken), user, type(uint256).max, block.timestamp + 30 days, v, r, s);
    }

    function testRequestOrderWithPermitSingle() public {
        vm.prank(user);
        issuer.multicall(calls);
    }

    function testRequestOrderWithPermit(uint256 permitDeadline, uint256 orderAmount) public {
        vm.assume(permitDeadline > block.timestamp);
        vm.assume(orderAmount > 1_000_000);

        uint256 fees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));

        IOrderProcessor.Order memory neworder = order;
        neworder.paymentTokenQuantity = orderAmount;
        uint256 quantityIn = neworder.paymentTokenQuantity + fees;

        SigUtils.Permit memory newpermit = SigUtils.Permit({
            owner: user,
            spender: address(issuer),
            value: quantityIn,
            nonce: 0,
            deadline: permitDeadline
        });

        bytes32 digest = sigUtils.getTypedDataHash(newpermit);

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(userPrivateKey, digest);

        bytes[] memory newcalls = new bytes[](2);
        newcalls[0] = abi.encodeWithSelector(
            issuer.selfPermit.selector, address(paymentToken), newpermit.owner, quantityIn, permitDeadline, v2, r2, s2
        );
        newcalls[1] = abi.encodeWithSelector(issuer.createOrderStandardFees.selector, neworder);
        vm.prank(user);
        issuer.multicall(newcalls);
    }
}
