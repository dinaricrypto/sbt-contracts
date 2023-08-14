// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Forwarder} from "../src/forwarder/Forwarder.sol";
import {Nonces} from "../src/common/Nonces.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import {TokenLockCheck, ITokenLockCheck} from "../src/TokenLockCheck.sol";
import {BuyOrderIssuer, OrderProcessor} from "../src/issuer/BuyOrderIssuer.sol";
import {SellOrderProcessor} from "../src/issuer/SellOrderProcessor.sol";
import "./utils/SigUtils.sol";
import "../src/issuer/IOrderBridge.sol";
import "./utils/mocks/MockToken.sol";
import "./utils/mocks/MockdShare.sol";
import "./utils/SigMeta.sol";
import "./utils/SigPrice.sol";
import "../src/forwarder/PriceAttestationConsumer.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {FeeLib} from "../src/FeeLib.sol";

contract ForwarderTest is Test {
    event TrustedOracleSet(address indexed oracle, bool isTrusted);
    event PriceRecencyThresholdSet(uint256 threshold);
    event RelayerSet(address indexed relayer, bool isRelayer);
    event BuyOrderIssuerSet(address indexed buyOrderIssuer);
    event DirectBuyIssuerSet(address indexed directBuyIssuer);
    event SellOrderProcessorSet(address indexed sellOrderProcessor);
    event LimitBuyIssuerSet(address indexed limitBuyIssuer);
    event LimitSellProcessorSet(address indexed limitSellProcessor);
    event OrderRequested(address indexed recipient, uint256 indexed index, IOrderBridge.Order order);
    event FeeUpdated(uint256 newFeeBps);
    event CancellationFeeUpdated(uint256 newCancellationFee);

    Forwarder public forwarder;
    BuyOrderIssuer public issuer;
    SellOrderProcessor public sellIssuer;
    OrderFees public orderFees;
    MockToken public paymentToken;
    dShare public token;

    SigMeta public sigMeta;
    SigPrice public sigPrice;
    SigUtils public paymentSigUtils;
    SigUtils public shareSigUtils;
    IOrderBridge.Order public dummyOrder;
    TokenLockCheck tokenLockCheck;

    uint24 percentageFeeRate;

    uint256 public userPrivateKey;
    uint256 public relayerPrivateKey;
    uint256 public ownerPrivateKey;
    uint256 flatFee;
    uint256 dummyOrderFees;
    // price of payment token in wei, accounting for decimals
    uint256 paymentTokenPrice;

    address public user;
    address public relayer;
    address public owner;
    address constant treasury = address(4);
    address constant operator = address(3);

    uint64 priceRecencyThreshold = 30 seconds;

    function setUp() public {
        userPrivateKey = 0x01;
        relayerPrivateKey = 0x02;
        ownerPrivateKey = 0x03;
        relayer = vm.addr(relayerPrivateKey);
        user = vm.addr(userPrivateKey);
        owner = vm.addr(ownerPrivateKey);

        token = new MockdShare();
        paymentToken = new MockToken();
        orderFees = new OrderFees(address(this), 1 ether, 5_000);
        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(paymentToken));

        // wei per USD (1 ether wei / ETH price in USD) * USD per USDC base unit (USDC price in USD / 10 ** USDC decimals)
        // e.g. (1 ether / 1867) * (0.997 / 10 ** paymentToken.decimals());
        paymentTokenPrice = uint256(0.997 ether) / 1867 / 10 ** paymentToken.decimals();

        issuer = new BuyOrderIssuer(address(this), treasury, orderFees, tokenLockCheck);
        sellIssuer = new SellOrderProcessor(address(this), treasury, orderFees, tokenLockCheck);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.BURNER_ROLE(), address(issuer));
        token.grantRole(token.BURNER_ROLE(), address(sellIssuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
        sellIssuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        sellIssuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        sellIssuer.grantRole(issuer.OPERATOR_ROLE(), operator);

        vm.startPrank(owner); // we set an owner to deploy forwarder
        forwarder = new Forwarder(priceRecencyThreshold);
        forwarder.setBuyOrderIssuer(address(issuer));
        forwarder.setSellOrderProcessor(address(sellIssuer));
        forwarder.setTrustedOracle(relayer, true);
        forwarder.setRelayer(relayer, true);
        vm.stopPrank();

        sigMeta = new SigMeta(forwarder.DOMAIN_SEPARATOR());
        sigPrice = new SigPrice(forwarder.DOMAIN_SEPARATOR());
        paymentSigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());
        shareSigUtils = new SigUtils(token.DOMAIN_SEPARATOR());

        (flatFee, percentageFeeRate) = issuer.getFeeRatesForOrder(address(paymentToken));
        dummyOrderFees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, 100 ether);

        dummyOrder = IOrderBridge.Order({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: false,
            orderType: IOrderBridge.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 100 ether,
            price: 0,
            tif: IOrderBridge.TIF.GTC
        });

        // set fees
        vm.prank(owner);
        forwarder.setFeeBps(100);
    }

    function testDeployment(address setRelayer, uint64 setRecency, uint256 cancellationFee) public {
        assertEq(forwarder.owner(), owner);
        assertEq(forwarder.priceRecencyThreshold(), priceRecencyThreshold);
        assertEq(forwarder.feeBps(), 100);

        vm.expectRevert("Ownable: caller is not the owner");
        forwarder.setTrustedOracle(setRelayer, true);
        vm.expectEmit(true, true, true, true);
        emit TrustedOracleSet(setRelayer, true);
        vm.prank(owner);
        forwarder.setTrustedOracle(setRelayer, true);
        assertEq(forwarder.isTrustedOracle(setRelayer), true);

        vm.expectRevert("Ownable: caller is not the owner");
        forwarder.setFeeBps(200);

        vm.expectEmit(true, true, true, true);
        emit FeeUpdated(100);
        vm.prank(owner);
        forwarder.setFeeBps(100);

        vm.expectRevert("Ownable: caller is not the owner");
        forwarder.setPriceRecencyThreshold(setRecency);
        vm.expectEmit(true, true, true, true);
        emit PriceRecencyThresholdSet(setRecency);
        vm.prank(owner);
        forwarder.setPriceRecencyThreshold(setRecency);
        assertEq(forwarder.priceRecencyThreshold(), setRecency);
        bytes32 domainSeparator = forwarder.DOMAIN_SEPARATOR();
        assert(domainSeparator != bytes32(0));

        vm.expectRevert("Ownable: caller is not the owner");
        forwarder.setCancellationFee(cancellationFee);
        vm.expectEmit(true, true, true, true);
        emit CancellationFeeUpdated(cancellationFee);
        vm.prank(owner);
        forwarder.setCancellationFee(cancellationFee);
    }

    function testAddProcessor(address setIssuer) public {
        vm.expectRevert("Ownable: caller is not the owner");
        forwarder.setBuyOrderIssuer(setIssuer);
        vm.expectRevert("Ownable: caller is not the owner");
        forwarder.setSellOrderProcessor(setIssuer);
        vm.expectRevert("Ownable: caller is not the owner");
        forwarder.setDirectBuyIssuer(setIssuer);

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit BuyOrderIssuerSet(setIssuer);
        forwarder.setBuyOrderIssuer(setIssuer);
        vm.expectEmit(true, true, true, true);
        emit SellOrderProcessorSet(setIssuer);
        forwarder.setSellOrderProcessor(setIssuer);
        vm.expectEmit(true, true, true, true);
        emit DirectBuyIssuerSet(setIssuer);
        forwarder.setDirectBuyIssuer(setIssuer);
        vm.expectEmit(true, true, true, true);
        emit LimitBuyIssuerSet(setIssuer);
        forwarder.setLimitBuyIssuer(setIssuer);
        vm.expectEmit(true, true, true, true);
        emit LimitSellProcessorSet(setIssuer);
        forwarder.setLimitSellProcessor(setIssuer);

        Forwarder.SupportedModules memory modules = forwarder.getSupportedModules();
        assertEq(modules.buyOrderIssuer, setIssuer);
        assertEq(modules.sellOrderProcessor, setIssuer);
        assertEq(modules.directBuyIssuer, setIssuer);
        assertEq(modules.limitBuyIssuer, setIssuer);
        assertEq(modules.limitSellProcessor, setIssuer);
    }

    function testRelayer(address setRelayer) public {
        vm.expectRevert("Ownable: caller is not the owner");
        forwarder.setRelayer(setRelayer, true);

        vm.expectEmit(true, true, true, true);
        emit RelayerSet(setRelayer, true);
        vm.prank(owner);
        forwarder.setRelayer(setRelayer, true);
    }

    function testRequestOrderThroughForwarder() public {
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, dummyOrder.paymentTokenQuantity);

        uint256 quantityIn = dummyOrder.paymentTokenQuantity + fees;

        IOrderBridge.Order memory order = dummyOrder;

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, order);

        uint256 nonce = 0;

        // 4. Mint tokens
        deal(address(paymentToken), user, quantityIn * 1e6);

        //  Prepare PriceAttestation
        PriceAttestationConsumer.PriceAttestation memory attestation = preparePriceAttestation();

        //  Prepare ForwardRequest
        Forwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, attestation, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        bytes32 id = issuer.getOrderId(order.recipient, 0);

        uint256 userBalanceBefore = paymentToken.balanceOf(user);
        uint256 issuerBalanceBefore = paymentToken.balanceOf(address(issuer));

        // 1. Request order
        vm.expectEmit(true, true, true, true);
        emit OrderRequested(user, 0, order);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        assertTrue(issuer.isOrderActive(id));
        assertEq(issuer.getRemainingOrder(id), order.paymentTokenQuantity);
        assertEq(issuer.numOpenOrders(), 1);

        assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + quantityIn);
        assertEq(paymentToken.balanceOf(address(user)), userBalanceBefore - quantityIn);
        assertEq(issuer.escrowedBalanceOf(order.paymentToken, user), quantityIn);
    }

    function testForwarderCancellationFeeSet(uint256 cancellationFee) public {
        bytes memory dataRequest = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        vm.assume(cancellationFee < 10e6);

        vm.prank(owner);
        forwarder.setCancellationFee(cancellationFee);

        deal(address(paymentToken), user, (dummyOrder.paymentTokenQuantity + dummyOrderFees + cancellationFee) * 1e6);

        PriceAttestationConsumer.PriceAttestation memory attestation = preparePriceAttestation();

        uint256 nonce = 0;
        // prepare request meta transaction
        Forwarder.ForwardRequest memory metaTx1 =
            prepareForwardRequest(user, address(issuer), dataRequest, nonce, attestation, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx1);

        uint256 balanceUserBeforeOrder = IERC20(address(paymentToken)).balanceOf(user);

        // set a request
        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        // check if cancellation fees has been taken by forwarder
        assertEq(
            IERC20(address(paymentToken)).balanceOf(address(user)),
            balanceUserBeforeOrder - (dummyOrder.paymentTokenQuantity + dummyOrderFees)
        );

        // update nonce
        nonce += 1;

        bytes memory dataCancel = abi.encodeWithSelector(issuer.requestCancel.selector, user, 0);
        Forwarder.ForwardRequest memory metaTx2 =
            prepareForwardRequest(user, address(issuer), dataCancel, nonce, attestation, userPrivateKey);
        multicalldata = new bytes[](1);
        multicalldata[0] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx2);

        uint256 balanceUserBeforeCancel = IERC20(address(paymentToken)).balanceOf(user);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        // there is no payment for cancellation order
        assertEq(IERC20(address(paymentToken)).balanceOf(address(user)), balanceUserBeforeCancel);
    }

    function testSellOrder() public {
        IOrderBridge.Order memory order = dummyOrder;
        order.sell = true;
        order.assetTokenQuantity = dummyOrder.paymentTokenQuantity;

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, order);

        uint256 nonce = 0;

        deal(address(token), user, order.assetTokenQuantity * 1e6);
        deal(address(paymentToken), user, order.paymentTokenQuantity * 1e6);

        //  Prepare PriceAttestation
        PriceAttestationConsumer.PriceAttestation memory attestation = preparePriceAttestation();

        //  Prepare ForwardRequest
        Forwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(sellIssuer), data, nonce, attestation, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](3);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = preparePermitCall(shareSigUtils, address(token), user, userPrivateKey, nonce);
        multicalldata[2] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        bytes32 id = sellIssuer.getOrderId(order.recipient, 0);

        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 issuerBalanceBefore = token.balanceOf(address(issuer));
        vm.expectEmit(true, true, true, true);
        emit OrderRequested(order.recipient, 0, order);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        assertTrue(sellIssuer.isOrderActive(id));
        assertEq(sellIssuer.getRemainingOrder(id), order.assetTokenQuantity);
        assertEq(sellIssuer.numOpenOrders(), 1);
        assertEq(token.balanceOf(address(sellIssuer)), order.assetTokenQuantity);
        assertEq(token.balanceOf(user), userBalanceBefore - order.assetTokenQuantity);
        assertEq(token.balanceOf(address(sellIssuer)), issuerBalanceBefore + order.assetTokenQuantity);
        assertEq(sellIssuer.escrowedBalanceOf(order.assetToken, user), order.assetTokenQuantity);
    }

    function testRequestOrderRevertStalePrice() public {
        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        uint256 nonce = 0;

        SigPrice.PriceAttestation memory priceAttestation = SigPrice.PriceAttestation({
            token: address(paymentToken),
            price: 1e6,
            chainId: block.chainid,
            timestamp: 100
        });
        bytes32 digestPrice = sigPrice.getTypedDataHashForPriceAttestation(priceAttestation);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerPrivateKey, digestPrice);
        PriceAttestationConsumer.PriceAttestation memory attestation = PriceAttestationConsumer.PriceAttestation({
            token: address(paymentToken),
            price: 1e6,
            timestamp: uint64(block.timestamp),
            chainId: block.chainid,
            signature: abi.encodePacked(r, s, v)
        });

        // move time forward
        vm.warp(block.timestamp + priceRecencyThreshold + 1);

        Forwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, attestation, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        vm.expectRevert(PriceAttestationConsumer.StalePrice.selector);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);
    }

    function testUnsupportedCall() public {
        bytes memory data = abi.encodeWithSignature("requestUnsupported((address,address,address,uint256))", dummyOrder);

        deal(address(paymentToken), user, dummyOrder.paymentTokenQuantity * 1e6);

        uint256 nonce = 0;

        PriceAttestationConsumer.PriceAttestation memory attestation = preparePriceAttestation();
        Forwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, attestation, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        vm.expectRevert(Forwarder.UnsupportedCall.selector);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);
    }

    function testRequestOrderRevertInvalidRelayer() public {
        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        uint256 nonce = 0;

        //Prepare PriceAttestation
        PriceAttestationConsumer.PriceAttestation memory attestation = preparePriceAttestation();

        //Prepare ForwardRequest
        Forwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, attestation, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        vm.expectRevert(Forwarder.UserNotRelayer.selector);
        forwarder.multicall(multicalldata);
    }

    function testRequestOrderRevertInvalidDeadline() public {
        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        uint256 nonce = 0;

        //  Prepare PriceAttestation
        PriceAttestationConsumer.PriceAttestation memory attestation = preparePriceAttestation();

        //  Prepare ForwardRequest
        Forwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, attestation, userPrivateKey);

        metaTx.deadline = 0;
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        vm.expectRevert(Forwarder.ExpiredRequest.selector);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);
    }

    function testRequestOrderPausedRevertThroughFordwarder(uint256 quantityIn) public {
        vm.assume(quantityIn < 100 ether);

        IOrderBridge.Order memory order = dummyOrder;
        order.paymentTokenQuantity = quantityIn;
        issuer.setOrdersPaused(true);

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, order);

        deal(address(paymentToken), user, (order.paymentTokenQuantity + dummyOrderFees) * 1e6);

        uint256 nonce = 0;

        //  Prepare PriceAttestation
        PriceAttestationConsumer.PriceAttestation memory attestation = preparePriceAttestation();

        //  Prepare ForwardRequest
        Forwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, attestation, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        vm.expectRevert(OrderProcessor.Paused.selector);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);
    }

    function testRequestCancel() public {
        IOrderBridge.Order memory order = dummyOrder;

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, order);

        uint256 nonce = 0;

        deal(address(paymentToken), user, order.paymentTokenQuantity * 1e6);

        //  Prepare PriceAttestation
        PriceAttestationConsumer.PriceAttestation memory attestation = preparePriceAttestation();

        //  Prepare ForwardRequest
        Forwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, attestation, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        nonce += 1;
        bytes memory dataCancel = abi.encodeWithSelector(issuer.requestCancel.selector, user, 0);
        Forwarder.ForwardRequest memory metaTx1 =
            prepareForwardRequest(user, address(issuer), dataCancel, nonce, attestation, userPrivateKey);
        multicalldata = new bytes[](1);
        multicalldata[0] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx1);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);
        assertEq(issuer.cancelRequested(issuer.getOrderId(order.recipient, 0)), true);
    }

    function testInvaldUserNonce() public {
        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        uint256 nonce = 1;

        // Mint
        deal(address(paymentToken), user, dummyOrder.paymentTokenQuantity * 1e6);

        //  Prepare PriceAttestation
        PriceAttestationConsumer.PriceAttestation memory attestation = preparePriceAttestation();

        //  Prepare ForwardRequest
        Forwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, attestation, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, 0);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(Nonces.InvalidAccountNonce.selector, user, 0));
        forwarder.multicall(multicalldata);

        uint256 userNonce = forwarder.nonces(user);
        assertEq(userNonce, 0);
    }

    function testrequestOrderModuleNotFound() public {
        BuyOrderIssuer issuer1 = new BuyOrderIssuer(address(this), treasury, orderFees, tokenLockCheck);

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        uint256 nonce = 0;

        // Mint
        deal(address(paymentToken), user, dummyOrder.paymentTokenQuantity * 1e6);

        // 4. Prepare PriceAttestation
        PriceAttestationConsumer.PriceAttestation memory attestation = preparePriceAttestation();

        //  Prepare ForwardRequest
        Forwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer1), data, nonce, attestation, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        vm.expectRevert(Forwarder.InvalidModuleAddress.selector);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);
    }

    function testRequestCancelNotRequesterReverts() public {
        IOrderBridge.Order memory order = dummyOrder;

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, order);

        uint256 nonce = 0;

        deal(address(paymentToken), user, dummyOrder.paymentTokenQuantity + dummyOrderFees * 1e6);

        //  Prepare PriceAttestation
        PriceAttestationConsumer.PriceAttestation memory attestation = preparePriceAttestation();

        //  Prepare ForwardRequest
        Forwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, attestation, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        bytes32 id = issuer.getOrderId(order.recipient, 0);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        bytes memory dataCancel = abi.encodeWithSelector(issuer.requestCancel.selector, user, 0);
        Forwarder.ForwardRequest memory metaTx1 =
            prepareForwardRequest(relayer, address(issuer), dataCancel, nonce, attestation, userPrivateKey);
        multicalldata = new bytes[](1);
        multicalldata[0] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx1);

        vm.expectRevert(Forwarder.InvalidSigner.selector);
        vm.prank(relayer);
        forwarder.forwardFunctionCall(metaTx1);
        assertEq(forwarder.orderSigners(id), user);
    }

    // utils functions

    function preparePriceAttestation() internal view returns (PriceAttestationConsumer.PriceAttestation memory) {
        SigPrice.PriceAttestation memory priceAttestation = SigPrice.PriceAttestation({
            token: address(paymentToken),
            price: paymentTokenPrice,
            timestamp: uint64(block.timestamp),
            chainId: block.chainid
        });
        bytes32 digestPrice = sigPrice.getTypedDataHashForPriceAttestation(priceAttestation);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerPrivateKey, digestPrice);
        PriceAttestationConsumer.PriceAttestation memory attestation = PriceAttestationConsumer.PriceAttestation({
            token: priceAttestation.token,
            price: priceAttestation.price,
            timestamp: priceAttestation.timestamp,
            chainId: priceAttestation.chainId,
            signature: abi.encodePacked(r, s, v)
        });
        return attestation;
    }

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
            deadline: 30 days
        });
        bytes32 digest = permitSigUtils.getTypedDataHash(sigPermit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
        return abi.encodeWithSelector(
            forwarder.selfPermit.selector, permitToken, sigPermit.owner, sigPermit.value, sigPermit.deadline, v, r, s
        );
    }

    function prepareForwardRequest(
        address _user,
        address to,
        bytes memory data,
        uint256 nonce,
        PriceAttestationConsumer.PriceAttestation memory attestation,
        uint256 _privateKey
    ) internal view returns (Forwarder.ForwardRequest memory) {
        SigMeta.ForwardRequest memory MetaTx = SigMeta.ForwardRequest({
            user: _user,
            to: to,
            data: data,
            deadline: 30 days,
            nonce: nonce,
            paymentTokenOraclePrice: attestation
        });

        bytes32 digestMeta = sigMeta.getHashToSign(MetaTx);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(_privateKey, digestMeta);

        Forwarder.ForwardRequest memory metaTx = Forwarder.ForwardRequest({
            user: _user,
            to: to,
            data: data,
            deadline: 30 days,
            nonce: nonce,
            paymentTokenOraclePrice: attestation,
            signature: abi.encodePacked(r2, s2, v2)
        });

        return metaTx;
    }
}
