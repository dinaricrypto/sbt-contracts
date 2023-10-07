// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Forwarder, IForwarder} from "../../src/forwarder/Forwarder.sol";
import {Nonces} from "../../src/common/Nonces.sol";
import {TokenLockCheck, ITokenLockCheck} from "../../src/TokenLockCheck.sol";
import {BuyProcessor, OrderProcessor} from "../../src/orders/BuyProcessor.sol";
import {SellProcessor} from "../../src/orders/SellProcessor.sol";
import {BuyUnlockedProcessor} from "../../src/orders/BuyUnlockedProcessor.sol";
import "../utils/SigUtils.sol";
import "../../src/orders/IOrderProcessor.sol";
import "../utils/mocks/MockToken.sol";
import "../utils/mocks/MockdShare.sol";
import "../utils/SigMeta.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {FeeLib} from "../../src/common/FeeLib.sol";

contract ForwarderTest is Test {
    event TrustedOracleSet(address indexed oracle, bool isTrusted);
    event PriceRecencyThresholdSet(uint256 threshold);
    event RelayerSet(address indexed relayer, bool isRelayer);
    event SupportedModuleSet(address indexed module, bool isSupported);
    event FeeUpdated(uint256 feeBps);
    event CancellationGasCostUpdated(uint256 newCancellationGasCost);
    event OrderRequested(address indexed recipient, uint256 indexed index, IOrderProcessor.Order order);
    event EscrowTaken(address indexed recipient, uint256 indexed index, uint256 amount);
    event EscrowReturned(address indexed recipient, uint256 indexed index, uint256 amount);
    event PaymentOracleUpdated(address paymentToken, address oracle);
    event UserOperationSponsored(
        address indexed user, uint256 actualTokenCharge, uint256 actualGasCost, uint256 actualTokenPrice
    );

    error InsufficientBalance();

    Forwarder public forwarder;
    BuyProcessor public issuer;
    SellProcessor public sellIssuer;
    BuyUnlockedProcessor public directBuyIssuer;
    MockToken public paymentToken;
    dShare public token;

    SigMeta public sigMeta;
    SigUtils public paymentSigUtils;
    SigUtils public shareSigUtils;
    IOrderProcessor.Order public dummyOrder;
    TokenLockCheck tokenLockCheck;

    uint24 percentageFeeRate;

    uint256 public userPrivateKey;
    uint256 public relayerPrivateKey;
    uint256 public ownerPrivateKey;
    uint256 flatFee;
    uint256 dummyOrderFees;

    address public user;
    address public relayer;
    address public owner;
    address constant treasury = address(4);
    address constant operator = address(3);
    address constant usdcPriceOracle = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

    function setUp() public {
        userPrivateKey = 0x1;
        relayerPrivateKey = 0x2;
        ownerPrivateKey = 0x3;
        relayer = vm.addr(relayerPrivateKey);
        user = vm.addr(userPrivateKey);
        owner = vm.addr(ownerPrivateKey);

        token = new MockdShare();
        paymentToken = new MockToken("Money", "$");
        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(paymentToken));

        issuer = new BuyProcessor(address(this), treasury, 1 ether, 5_000, tokenLockCheck);
        sellIssuer = new SellProcessor(address(this), treasury, 1 ether, 5_000, tokenLockCheck);
        directBuyIssuer = new BuyUnlockedProcessor(address(this), treasury, 1 ether, 5_000, tokenLockCheck);

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.BURNER_ROLE(), address(issuer));
        token.grantRole(token.BURNER_ROLE(), address(sellIssuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
        sellIssuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        sellIssuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        sellIssuer.grantRole(issuer.OPERATOR_ROLE(), operator);
        directBuyIssuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        directBuyIssuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        directBuyIssuer.grantRole(issuer.OPERATOR_ROLE(), operator);

        vm.startPrank(owner); // we set an owner to deploy forwarder
        forwarder = new Forwarder();
        forwarder.setSupportedModule(address(issuer), true);
        forwarder.setSupportedModule(address(sellIssuer), true);
        forwarder.setSupportedModule(address(directBuyIssuer), true);
        forwarder.setRelayer(relayer, true);
        vm.stopPrank();

        // set issuer forwarder role
        issuer.grantRole(issuer.FORWARDER_ROLE(), address(forwarder));
        sellIssuer.grantRole(sellIssuer.FORWARDER_ROLE(), address(forwarder));
        directBuyIssuer.grantRole(directBuyIssuer.FORWARDER_ROLE(), address(forwarder));

        sigMeta = new SigMeta(forwarder.DOMAIN_SEPARATOR());
        paymentSigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());
        shareSigUtils = new SigUtils(token.DOMAIN_SEPARATOR());

        (flatFee, percentageFeeRate) = issuer.getFeeRatesForOrder(address(paymentToken));
        dummyOrderFees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, 100 ether);

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

        // set fees
        vm.prank(owner);
        forwarder.setFeeBps(100);
        vm.prank(owner);
        forwarder.updateOracle(address(paymentToken), usdcPriceOracle);
    }

    function testUpdateOracle(address _paymentToken, address _oracle) public {
        vm.expectRevert("Ownable: caller is not the owner");
        forwarder.updateOracle(_paymentToken, _oracle);

        vm.expectEmit(true, true, true, true);
        emit PaymentOracleUpdated(_paymentToken, _oracle);
        vm.prank(owner);
        forwarder.updateOracle(_paymentToken, _oracle);
    }

    function testDeployment(uint256 cancellationCost) public {
        assertEq(forwarder.owner(), owner);
        assertEq(forwarder.feeBps(), 100);

        vm.expectRevert("Ownable: caller is not the owner");
        forwarder.setFeeBps(200);

        vm.expectEmit(true, true, true, true);
        emit FeeUpdated(100);
        vm.prank(owner);
        forwarder.setFeeBps(100);

        bytes32 domainSeparator = forwarder.DOMAIN_SEPARATOR();
        assert(domainSeparator != bytes32(0));

        vm.expectRevert("Ownable: caller is not the owner");
        forwarder.setCancellationGasCost(cancellationCost);
        vm.expectEmit(true, true, true, true);
        emit CancellationGasCostUpdated(cancellationCost);
        vm.prank(owner);
        forwarder.setCancellationGasCost(cancellationCost);
    }

    function testAddProcessor(address setIssuer) public {
        vm.expectRevert("Ownable: caller is not the owner");
        forwarder.setSupportedModule(setIssuer, true);

        vm.expectEmit(true, true, true, true);
        emit SupportedModuleSet(setIssuer, true);
        vm.prank(owner);
        forwarder.setSupportedModule(setIssuer, true);
        assert(forwarder.isSupportedModule(setIssuer));

        vm.expectEmit(true, true, true, true);
        emit SupportedModuleSet(setIssuer, false);
        vm.prank(owner);
        forwarder.setSupportedModule(setIssuer, false);
        assert(!forwarder.isSupportedModule(setIssuer));
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
        uint256 quantityIn = dummyOrder.paymentTokenQuantity + dummyOrderFees;

        IOrderProcessor.Order memory order = dummyOrder;

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, order);

        uint256 nonce = 0;

        // 4. Mint tokens
        deal(address(paymentToken), user, quantityIn * 1e6);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), address(paymentToken), data, nonce, userPrivateKey);

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

        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(id), dummyOrder.paymentTokenQuantity);
        assertEq(issuer.numOpenOrders(), 1);

        assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + quantityIn);
        assertLt(paymentToken.balanceOf(address(user)), userBalanceBefore - quantityIn);
        assertEq(issuer.escrowedBalanceOf(order.paymentToken, user), quantityIn);
    }

    function testRequestUserOperationEvent() public {
        uint256 quantityIn = dummyOrder.paymentTokenQuantity + dummyOrderFees;

        IOrderProcessor.Order memory order = dummyOrder;

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, order);

        uint256 nonce = 0;

        // 4. Mint tokens
        deal(address(paymentToken), user, quantityIn * 1e6);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), address(paymentToken), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        uint256 totalGasCostInWei = (gasleft() + forwarder.cancellationGasCost()) * tx.gasprice;

        // 1. Request order
        vm.expectEmit(true, true, true, false);
        // emit doesn't check data, just event has been emit
        emit UserOperationSponsored(
            metaTx.user,
            order.paymentTokenQuantity,
            totalGasCostInWei,
            forwarder.getPaymentPriceInWei(order.paymentToken)
        );
        vm.prank(relayer);
        forwarder.multicall(multicalldata);
    }

    function testForwarderCancellationFeeSet(uint256 cancellationCost) public {
        bytes memory dataRequest = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        vm.assume(cancellationCost < 10e6);

        vm.prank(owner);
        forwarder.setCancellationGasCost(cancellationCost);

        deal(address(paymentToken), user, (dummyOrder.paymentTokenQuantity + dummyOrderFees + cancellationCost) * 1e6);

        uint256 nonce = 0;
        // prepare request meta transaction
        IForwarder.ForwardRequest memory metaTx1 =
            prepareForwardRequest(user, address(issuer), address(paymentToken), dataRequest, nonce, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx1);

        uint256 balanceUserBeforeOrder = IERC20(address(paymentToken)).balanceOf(user);

        // set a request
        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        // check if cancellation fees has been taken by forwarder
        assertLt(
            IERC20(address(paymentToken)).balanceOf(address(user)),
            balanceUserBeforeOrder - (dummyOrder.paymentTokenQuantity + dummyOrderFees)
        );

        uint256 balanceUserBeforeCancel = IERC20(address(paymentToken)).balanceOf(user);

        // update nonce
        nonce += 1;

        bytes memory dataCancel = abi.encodeWithSelector(issuer.requestCancel.selector, user, 0);
        Forwarder.ForwardRequest memory metaTx2 =
            prepareForwardRequest(user, address(issuer), address(paymentToken), dataCancel, nonce, userPrivateKey);
        multicalldata = new bytes[](1);
        multicalldata[0] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx2);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        // there is no payment for cancellation order
        assertEq(IERC20(address(paymentToken)).balanceOf(address(user)), balanceUserBeforeCancel);
    }

    function testSellOrder() public {
        IOrderProcessor.Order memory order = dummyOrder;
        order.sell = true;
        order.assetTokenQuantity = dummyOrder.paymentTokenQuantity;

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, order);

        uint256 nonce = 0;

        deal(address(token), user, order.assetTokenQuantity * 1e6);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(sellIssuer), address(paymentToken), data, nonce, userPrivateKey);

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

        vm.expectRevert(InsufficientBalance.selector);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        // mint paymentToken Balance ex: USDC
        deal(address(paymentToken), user, order.paymentTokenQuantity * 1e6);
        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(user);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        uint256 paymentTokenBalanceAfter = paymentToken.balanceOf(user);

        assertEq(uint8(sellIssuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(sellIssuer.getUnfilledAmount(id), order.assetTokenQuantity);
        assertEq(sellIssuer.numOpenOrders(), 1);
        assertEq(token.balanceOf(address(sellIssuer)), order.assetTokenQuantity);
        assertEq(token.balanceOf(user), userBalanceBefore - order.assetTokenQuantity);
        assertEq(token.balanceOf(address(sellIssuer)), issuerBalanceBefore + order.assetTokenQuantity);
        assertEq(sellIssuer.escrowedBalanceOf(order.assetToken, user), order.assetTokenQuantity);
        assert(paymentTokenBalanceBefore > paymentTokenBalanceAfter);
        // cost should be < 1e6 for gas cost
        // assertLt(paymentTokenBalanceBefore - paymentTokenBalanceAfter, 1e6);
    }

    function testTakeEscrowBuyUnlockedOrder(uint256 takeAmount) public {
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, dummyOrder.paymentTokenQuantity);

        uint256 quantityIn = dummyOrder.paymentTokenQuantity + fees;

        IOrderProcessor.Order memory order = dummyOrder;

        bytes memory data = abi.encodeWithSelector(directBuyIssuer.requestOrder.selector, order);

        uint256 nonce = 0;

        // 4. Mint tokens
        deal(address(paymentToken), user, quantityIn * 1e6);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(directBuyIssuer), address(paymentToken), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        bytes32 id = directBuyIssuer.getOrderId(order.recipient, 0);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        // test take escrow
        if (takeAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            directBuyIssuer.takeEscrow(order, 0, takeAmount);
        } else if (takeAmount > order.paymentTokenQuantity) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            directBuyIssuer.takeEscrow(order, 0, takeAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit EscrowTaken(order.recipient, 0, takeAmount);
            vm.prank(operator);
            directBuyIssuer.takeEscrow(order, 0, takeAmount);
            assertEq(paymentToken.balanceOf(operator), takeAmount);
            assertEq(directBuyIssuer.getOrderEscrow(id), order.paymentTokenQuantity - takeAmount);
        }
    }

    function testReturnEscrowBuyUnlockedOrder(uint256 returnAmount) public {
        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, dummyOrder.paymentTokenQuantity);

        uint256 quantityIn = dummyOrder.paymentTokenQuantity + fees;

        IOrderProcessor.Order memory order = dummyOrder;

        bytes memory data = abi.encodeWithSelector(directBuyIssuer.requestOrder.selector, order);

        uint256 nonce = 0;

        // 4. Mint tokens
        deal(address(paymentToken), user, quantityIn * 1e6);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(directBuyIssuer), address(paymentToken), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        bytes32 id = directBuyIssuer.getOrderId(order.recipient, 0);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        vm.prank(operator);
        directBuyIssuer.takeEscrow(order, 0, order.paymentTokenQuantity);

        vm.prank(operator);
        paymentToken.increaseAllowance(address(directBuyIssuer), returnAmount);

        if (returnAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            directBuyIssuer.returnEscrow(order, 0, returnAmount);
        } else if (returnAmount > order.paymentTokenQuantity) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            directBuyIssuer.returnEscrow(order, 0, returnAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit EscrowReturned(order.recipient, 0, returnAmount);
            vm.prank(operator);
            directBuyIssuer.returnEscrow(order, 0, returnAmount);
            assertEq(directBuyIssuer.getOrderEscrow(id), returnAmount);
            assertEq(paymentToken.balanceOf(address(directBuyIssuer)), fees + returnAmount);
        }
    }

    function testRequestOrderNotApprovedByProcessorReverts() public {
        issuer.revokeRole(issuer.FORWARDER_ROLE(), address(forwarder));

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        uint256 nonce = 0;

        // 4. Mint tokens
        uint256 quantityIn = dummyOrder.paymentTokenQuantity + dummyOrderFees;
        deal(address(paymentToken), user, quantityIn);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), address(paymentToken), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        // 1. Request order
        vm.expectRevert(Forwarder.ForwarderNotApprovedByProcessor.selector);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);
    }

    function testUnsupportedCall() public {
        bytes memory data = abi.encodeWithSignature("requestUnsupported((address,address,address,uint256))", dummyOrder);

        deal(address(paymentToken), user, dummyOrder.paymentTokenQuantity * 1e6);

        uint256 nonce = 0;

        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), address(paymentToken), data, nonce, userPrivateKey);

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

        //Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), address(paymentToken), data, nonce, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        vm.expectRevert(Forwarder.UserNotRelayer.selector);
        forwarder.multicall(multicalldata);
    }

    function testRequestOrderRevertInvalidDeadline() public {
        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        uint256 nonce = 0;

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), address(paymentToken), data, nonce, userPrivateKey);

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

        IOrderProcessor.Order memory order = dummyOrder;
        order.paymentTokenQuantity = quantityIn;
        issuer.setOrdersPaused(true);

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        deal(address(paymentToken), user, (order.paymentTokenQuantity + dummyOrderFees) * 1e6);

        uint256 nonce = 0;

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), address(paymentToken), data, nonce, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        vm.expectRevert(OrderProcessor.Paused.selector);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);
    }

    function testRequestCancel() public {
        IOrderProcessor.Order memory order = dummyOrder;

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, order);

        uint256 nonce = 0;

        deal(address(paymentToken), user, order.paymentTokenQuantity * 1e6);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), address(paymentToken), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        nonce += 1;
        bytes memory dataCancel = abi.encodeWithSelector(issuer.requestCancel.selector, user, 0);
        Forwarder.ForwardRequest memory metaTx1 =
            prepareForwardRequest(user, address(issuer), address(paymentToken), dataCancel, nonce, userPrivateKey);
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

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), address(paymentToken), data, nonce, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, 0);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(Nonces.InvalidAccountNonce.selector, user, 0));
        forwarder.multicall(multicalldata);

        uint256 userNonce = forwarder.nonces(user);
        assertEq(userNonce, 0);
    }

    function testRequestOrderModuleNotFound() public {
        BuyProcessor issuer1 = new BuyProcessor(address(this), treasury, 1 ether, 5_000, tokenLockCheck);
        issuer1.grantRole(issuer1.FORWARDER_ROLE(), address(forwarder));

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        uint256 nonce = 0;

        // Mint
        deal(address(paymentToken), user, dummyOrder.paymentTokenQuantity * 1e6);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer1), address(paymentToken), data, nonce, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        vm.expectRevert(Forwarder.NotSupportedModule.selector);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);
    }

    function testRequestCancelNotRequesterReverts() public {
        IOrderProcessor.Order memory order = dummyOrder;

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, order);

        uint256 nonce = 0;

        deal(address(paymentToken), user, dummyOrder.paymentTokenQuantity + dummyOrderFees * 1e6);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), address(paymentToken), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        bytes32 id = issuer.getOrderId(order.recipient, 0);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        bytes memory dataCancel = abi.encodeWithSelector(issuer.requestCancel.selector, user, 0);
        Forwarder.ForwardRequest memory metaTx1 =
            prepareForwardRequest(relayer, address(issuer), address(paymentToken), dataCancel, nonce, userPrivateKey);
        multicalldata = new bytes[](1);
        multicalldata[0] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx1);

        vm.expectRevert(Forwarder.InvalidSigner.selector);
        vm.prank(relayer);
        forwarder.forwardFunctionCall(metaTx1);
        assertEq(forwarder.orderSigner(id), user);
    }

    function testCancel() public {
        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        uint256 nonce = 0;

        uint256 quantityIn = dummyOrder.paymentTokenQuantity + dummyOrderFees;
        uint256 userFunds = quantityIn * 1e6;
        deal(address(paymentToken), user, userFunds);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), address(paymentToken), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);
        // uint256 index = abi.decode(multiReturns[1], (uint256));

        uint256 balanceUserBefore = paymentToken.balanceOf(user);

        // cancel
        vm.prank(operator);
        issuer.cancelOrder(dummyOrder, 0, "test");
        assertEq(paymentToken.balanceOf(address(forwarder)), 0);
        assertEq(paymentToken.balanceOf(address(issuer)), 0);
        assertLt(paymentToken.balanceOf(address(user)), userFunds);
        assertEq(paymentToken.balanceOf(address(user)), balanceUserBefore + quantityIn);
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
            deadline: block.timestamp + 30 days
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
        address _paymentToken,
        bytes memory data,
        uint256 nonce,
        uint256 _privateKey
    ) internal view returns (IForwarder.ForwardRequest memory metaTx) {
        SigMeta.ForwardRequest memory MetaTx = SigMeta.ForwardRequest({
            user: _user,
            to: to,
            paymentToken: _paymentToken,
            data: data,
            deadline: uint64(block.timestamp + 30 days),
            nonce: nonce
        });

        bytes32 digestMeta = sigMeta.getHashToSign(MetaTx);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(_privateKey, digestMeta);

        metaTx = IForwarder.ForwardRequest({
            user: _user,
            to: to,
            paymentToken: _paymentToken,
            data: data,
            deadline: uint64(block.timestamp + 30 days),
            nonce: nonce,
            signature: abi.encodePacked(r2, s2, v2)
        });
    }
}
