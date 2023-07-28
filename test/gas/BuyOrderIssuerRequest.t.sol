// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import "../utils/mocks/MockdShare.sol";
import "../utils/SigUtils.sol";
import "../../src/issuer/BuyOrderIssuer.sol";
import "../../src/issuer/IOrderBridge.sol";
import {OrderFees, IOrderFees} from "../../src/issuer/OrderFees.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract BuyOrderIssuerRequestTest is Test {
    // More calls to permit and multicall for gas profiling

    dShare token;
    OrderFees orderFees;
    BuyOrderIssuer issuer;
    MockERC20 paymentToken;
    SigUtils sigUtils;

    uint256 userPrivateKey;
    address user;

    address constant operator = address(3);
    address constant treasury = address(4);

    uint8 v;
    bytes32 r;
    bytes32 s;

    OrderProcessor.OrderRequest order;
    bytes[] calls;

    function setUp() public {
        userPrivateKey = 0x01;
        user = vm.addr(userPrivateKey);

        token = new MockdShare();
        paymentToken = new MockERC20("Money", "$", 6);
        sigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());

        orderFees = new OrderFees(address(this), 1_000_000, 5_000);
        issuer = new BuyOrderIssuer(address(this), treasury, orderFees);
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);

        paymentToken.mint(user, type(uint256).max);

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: user,
            spender: address(issuer),
            value: type(uint256).max,
            nonce: 0,
            deadline: 30 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (v, r, s) = vm.sign(userPrivateKey, digest);

        order = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: 1 ether,
            price: 0
        });

        calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            issuer.selfPermit.selector, address(paymentToken), type(uint256).max, 30 days, v, r, s
        );
        calls[1] = abi.encodeWithSelector(issuer.requestOrder.selector, order, bytes32("0x01"));
    }

    function testSelfPermit() public {
        vm.prank(user);
        issuer.selfPermit(address(paymentToken), type(uint256).max, 30 days, v, r, s);
    }

    function testRequestOrderWithPermitSingle() public {
        vm.prank(user);
        issuer.multicall(calls);
    }

    function testRequestOrderWithPermit(uint256 permitDeadline, uint256 quantityIn, bytes32 salt) public {
        vm.assume(permitDeadline > block.timestamp);
        vm.assume(quantityIn > 1_000_000);

        SigUtils.Permit memory newpermit = SigUtils.Permit({
            owner: user,
            spender: address(issuer),
            value: quantityIn,
            nonce: 0,
            deadline: permitDeadline
        });

        bytes32 digest = sigUtils.getTypedDataHash(newpermit);

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(userPrivateKey, digest);

        OrderProcessor.OrderRequest memory neworder = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            quantityIn: quantityIn,
            price: 0
        });
        bytes[] memory newcalls = new bytes[](2);
        newcalls[0] = abi.encodeWithSelector(
            issuer.selfPermit.selector, address(paymentToken), quantityIn, permitDeadline, v2, r2, s2
        );
        newcalls[1] = abi.encodeWithSelector(issuer.requestOrder.selector, neworder, salt);
        vm.prank(user);
        issuer.multicall(newcalls);
    }
}
