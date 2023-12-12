// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {Forwarder, IForwarder} from "../../src/forwarder/Forwarder.sol";
import {Nonces} from "openzeppelin-contracts/contracts/utils/Nonces.sol";
import {TokenLockCheck, ITokenLockCheck} from "../../src/TokenLockCheck.sol";
import {OrderProcessor} from "../../src/orders/OrderProcessor.sol";
import "../utils/SigUtils.sol";
import "../../src/orders/IOrderProcessor.sol";
import {MockToken} from "../utils/mocks/MockToken.sol";
import "../utils/SigMetaUtils.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {FeeLib} from "../../src/common/FeeLib.sol";
import {ERC20, MockERC20} from "solady/test/utils/mocks/MockERC20.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// test that forwarder and processors do not assume dShares are dShares
contract dShareCompatTest is Test {
    Forwarder public forwarder;
    OrderProcessor public issuer;
    MockToken public paymentToken;
    ERC20 public token;

    SigMetaUtils public sigMeta;
    SigUtils public paymentSigUtils;
    SigUtils public shareSigUtils;
    IOrderProcessor.Order public dummyOrder;
    TokenLockCheck tokenLockCheck;

    uint24 percentageFeeRate;

    uint256 public userPrivateKey;
    uint256 public relayerPrivateKey;
    uint256 public ownerPrivateKey;
    uint256 public adminPrivateKey;
    uint256 flatFee;
    uint256 dummyOrderFees;
    // price of payment token in wei, accounting for decimals
    uint256 paymentTokenPrice;

    address public user;
    address public relayer;
    address public owner;
    address public admin;
    address constant treasury = address(4);
    address constant operator = address(3);
    address constant ethUSDOracle = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address constant usdcPriceOracle = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

    uint64 priceRecencyThreshold = 30 seconds;
    uint256 constant SELL_GAS_COST = 1000000;

    function setUp() public {
        userPrivateKey = 0x01;
        relayerPrivateKey = 0x02;
        ownerPrivateKey = 0x03;
        adminPrivateKey = 0x04;
        relayer = vm.addr(relayerPrivateKey);
        user = vm.addr(userPrivateKey);
        owner = vm.addr(ownerPrivateKey);
        admin = vm.addr(adminPrivateKey);

        vm.prank(admin);
        token = new MockERC20("Money", "$", 6);
        paymentToken = new MockToken("Money", "$");
        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(paymentToken));
        vm.stopPrank();

        // wei per USD (1 ether wei / ETH price in USD) * USD per USDC base unit (USDC price in USD / 10 ** USDC decimals)
        // e.g. (1 ether / 1867) * (0.997 / 10 ** paymentToken.decimals());
        paymentTokenPrice = uint256(0.997 ether) / 1867 / 10 ** paymentToken.decimals();

        OrderProcessor issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl),
                    abi.encodeCall(
                        OrderProcessor.initialize,
                        (
                            admin,
                            treasury,
                            OrderProcessor.FeeRates({
                                perOrderFeeBuy: 1 ether,
                                percentageFeeRateBuy: 5_000,
                                perOrderFeeSell: 1 ether,
                                percentageFeeRateSell: 5_000
                            }),
                            tokenLockCheck
                        )
                    )
                )
            )
        );

        vm.startPrank(admin);
        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        vm.startPrank(owner); // we set an owner to deploy forwarder
        forwarder = new Forwarder(ethUSDOracle, SELL_GAS_COST);
        forwarder.setSupportedModule(address(issuer), true);
        forwarder.setRelayer(relayer, true);
        forwarder.setPaymentOracle(address(paymentToken), usdcPriceOracle);
        vm.stopPrank();

        // set issuer forwarder role
        vm.startPrank(admin);
        issuer.grantRole(issuer.FORWARDER_ROLE(), address(forwarder));

        sigMeta = new SigMetaUtils(forwarder.DOMAIN_SEPARATOR());
        paymentSigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());
        shareSigUtils = new SigUtils(token.DOMAIN_SEPARATOR());
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

        (flatFee, percentageFeeRate) = issuer.getFeeRatesForOrder(user, false, address(paymentToken));
        dummyOrderFees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, 100 ether);

        // set fees
        vm.prank(owner);
        forwarder.setFeeBps(100);
    }

    function testRequestOrderThroughForwarder() public {
        uint256 quantityIn = dummyOrder.paymentTokenQuantity + dummyOrderFees;

        IOrderProcessor.Order memory order = dummyOrder;

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, order);

        uint256 nonce = 0;

        // Mint tokens
        deal(address(paymentToken), user, quantityIn * 1e6);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx);

        uint256 userBalanceBefore = paymentToken.balanceOf(user);
        uint256 issuerBalanceBefore = paymentToken.balanceOf(address(issuer));

        // 1. Request order
        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        assertEq(uint8(issuer.getOrderStatus(0)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(0), dummyOrder.paymentTokenQuantity);
        assertEq(issuer.numOpenOrders(), 1);

        assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + quantityIn);
        assertLt(paymentToken.balanceOf(address(user)), userBalanceBefore - quantityIn);
        assertEq(issuer.escrowedBalanceOf(order.paymentToken, user), quantityIn);
    }

    function testSellOrder() public {
        IOrderProcessor.Order memory order = dummyOrder;
        order.sell = true;
        order.assetTokenQuantity = dummyOrder.paymentTokenQuantity;

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, order);

        uint256 nonce = 0;

        deal(address(token), user, order.assetTokenQuantity * 1e6);
        deal(address(paymentToken), user, order.paymentTokenQuantity * 1e6);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](3);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = preparePermitCall(shareSigUtils, address(token), user, userPrivateKey, nonce);
        multicalldata[2] = abi.encodeWithSelector(forwarder.forwardRequestSellOrder.selector, metaTx);

        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 issuerBalanceBefore = token.balanceOf(address(issuer));

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        assertEq(uint8(issuer.getOrderStatus(0)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(0), order.assetTokenQuantity);
        assertEq(issuer.numOpenOrders(), 1);
        assertEq(token.balanceOf(address(issuer)), order.assetTokenQuantity);
        assertEq(token.balanceOf(user), userBalanceBefore - order.assetTokenQuantity);
        assertEq(token.balanceOf(address(issuer)), issuerBalanceBefore + order.assetTokenQuantity);
        assertEq(issuer.escrowedBalanceOf(order.assetToken, user), order.assetTokenQuantity);
    }

    function testRequestCancel() public {
        IOrderProcessor.Order memory order = dummyOrder;

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, order);

        uint256 nonce = 0;

        deal(address(paymentToken), user, order.paymentTokenQuantity * 1e6);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        nonce += 1;
        bytes memory dataCancel = abi.encodeWithSelector(issuer.requestCancel.selector, 0);
        Forwarder.ForwardRequest memory metaTx1 =
            prepareForwardRequest(user, address(issuer), dataCancel, nonce, userPrivateKey);
        multicalldata = new bytes[](1);
        multicalldata[0] = abi.encodeWithSelector(forwarder.forwardRequestCancel.selector, metaTx1);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);
        assertEq(issuer.cancelRequested(0), true);
    }

    // utils functions

    // set Permit for user
    function preparePermitCall(
        SigUtils permitSigUtils,
        address permitToken,
        address _user,
        uint256 _privateKey,
        uint256 _nonce
    ) internal view returns (bytes memory) {
        SigUtils.Permit memory sigPermit = SigUtils.Permit({
            owner: _user,
            spender: address(forwarder),
            value: type(uint256).max,
            nonce: _nonce,
            deadline: block.timestamp + 30 days
        });
        bytes32 digest = permitSigUtils.getTypedDataHash(sigPermit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
        return abi.encodeWithSelector(
            forwarder.selfPermit.selector, permitToken, sigPermit.owner, sigPermit.value, sigPermit.deadline, v, r, s
        );
    }

    function prepareForwardRequest(address _user, address to, bytes memory data, uint256 nonce, uint256 _privateKey)
        internal
        view
        returns (IForwarder.ForwardRequest memory metaTx)
    {
        SigMetaUtils.ForwardRequest memory MetaTx = SigMetaUtils.ForwardRequest({
            user: _user,
            to: to,
            data: data,
            deadline: uint64(block.timestamp + 30 days),
            nonce: nonce
        });

        bytes32 digestMeta = sigMeta.getHashToSign(MetaTx);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(_privateKey, digestMeta);

        metaTx = IForwarder.ForwardRequest({
            user: _user,
            to: to,
            data: data,
            deadline: uint64(block.timestamp + 30 days),
            nonce: nonce,
            signature: abi.encodePacked(r2, s2, v2)
        });
    }
}
