// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {ForwarderLink} from "../../src/forwarder/ForwarderLink.sol";
import {Forwarder, IForwarder} from "../../src/forwarder/Forwarder.sol";
import {Nonces} from "openzeppelin-contracts/contracts/utils/Nonces.sol";
import {TokenLockCheck, ITokenLockCheck} from "../../src/TokenLockCheck.sol";
import {OrderProcessor} from "../../src/orders/OrderProcessor.sol";
import {BuyUnlockedProcessor} from "../../src/orders/BuyUnlockedProcessor.sol";
import "../utils/SigUtils.sol";
import "../../src/orders/IOrderProcessor.sol";
import "../utils/mocks/MockToken.sol";
import "../utils/mocks/MockDShareFactory.sol";
import "../utils/SigMetaUtils.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {FeeLib} from "../../src/common/FeeLib.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import "prb-math/Common.sol" as PrbMath;
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ForwarderLinkTest is Test {
    event RelayerSet(address indexed relayer, bool isRelayer);
    event SupportedModuleSet(address indexed module, bool isSupported);
    event FeeUpdated(uint256 feeBps);
    event CancellationGasCostUpdated(uint256 newCancellationGasCost);

    event OrderRequested(uint256 indexed id, address indexed recipient, IOrderProcessor.Order order);
    event EscrowTaken(uint256 indexed id, address indexed recipient, uint256 amount);
    event EscrowReturned(uint256 indexed id, address indexed recipient, uint256 amount);

    event PaymentOracleSet(address indexed paymentToken, address indexed oracle);
    event EthUsdOracleSet(address indexed oracle);
    event UserOperationSponsored(
        address indexed user,
        address indexed paymentToken,
        uint256 actualTokenCharge,
        uint256 actualGasCost,
        uint256 actualTokenPrice
    );

    error InsufficientBalance();

    ForwarderLink public forwarder;
    OrderProcessor public issuerImpl;
    OrderProcessor public issuer;
    BuyUnlockedProcessor public directBuyIssuer;
    MockToken public paymentToken;
    MockDShareFactory public tokenFactory;
    DShare public token;

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

    address public user;
    address public relayer;
    address public owner;
    address public admin;
    address constant treasury = address(4);
    address constant operator = address(3);
    address constant ethUsdPriceOracle = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address constant usdcPriceOracle = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

    uint256 constant SELL_GAS_COST = 1000000;

    bytes private constant FORWARDREQUEST_TYPE =
        abi.encodePacked("ForwardRequest(address user,address to,bytes data,uint64 deadline,uint256 nonce)");
    bytes32 private constant FORWARDREQUEST_TYPEHASH = keccak256(FORWARDREQUEST_TYPE);

    function setUp() public {
        userPrivateKey = 0x1;
        relayerPrivateKey = 0x2;
        ownerPrivateKey = 0x3;
        adminPrivateKey = 0x4;
        relayer = vm.addr(relayerPrivateKey);
        user = vm.addr(userPrivateKey);
        owner = vm.addr(ownerPrivateKey);
        admin = vm.addr(adminPrivateKey);

        vm.startPrank(admin);
        tokenFactory = new MockDShareFactory();
        token = tokenFactory.deploy("Dinari Token", "dTKN");
        paymentToken = new MockToken("Money", "$");
        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(paymentToken));
        vm.stopPrank();

        issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl), abi.encodeCall(OrderProcessor.initialize, (admin, treasury, tokenLockCheck))
                )
            )
        );
        BuyUnlockedProcessor directBuyIssuerImpl = new BuyUnlockedProcessor();
        directBuyIssuer = BuyUnlockedProcessor(
            address(
                new ERC1967Proxy(
                    address(directBuyIssuerImpl),
                    abi.encodeCall(OrderProcessor.initialize, (admin, treasury, tokenLockCheck))
                )
            )
        );

        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), admin);
        token.grantRole(token.BURNER_ROLE(), address(issuer));

        OrderProcessor.FeeRates memory defaultFees = OrderProcessor.FeeRates({
            perOrderFeeBuy: 1 ether,
            percentageFeeRateBuy: 5_000,
            perOrderFeeSell: 1 ether,
            percentageFeeRateSell: 5_000
        });
        issuer.setDefaultFees(address(paymentToken), defaultFees);
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
        directBuyIssuer.setDefaultFees(address(paymentToken), defaultFees);
        directBuyIssuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        directBuyIssuer.grantRole(issuer.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        vm.startPrank(owner); // we set an owner to deploy forwarder
        forwarder = new ForwarderLink(ethUsdPriceOracle, SELL_GAS_COST);
        forwarder.setSupportedModule(address(issuer), true);
        forwarder.setSupportedModule(address(directBuyIssuer), true);
        forwarder.setRelayer(relayer, true);
        vm.stopPrank();

        // set issuer forwarder role
        vm.startPrank(admin);
        issuer.grantRole(issuer.FORWARDER_ROLE(), address(forwarder));
        directBuyIssuer.grantRole(directBuyIssuer.FORWARDER_ROLE(), address(forwarder));

        sigMeta = new SigMetaUtils(forwarder.DOMAIN_SEPARATOR());
        paymentSigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());
        shareSigUtils = new SigUtils(token.DOMAIN_SEPARATOR());
        vm.stopPrank();

        (flatFee, percentageFeeRate) = issuer.getFeeRatesForOrder(user, false, address(paymentToken));
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
            tif: IOrderProcessor.TIF.GTC,
            splitAmount: 0,
            splitRecipient: address(0)
        });

        // set fees
        vm.prank(owner);
        forwarder.setFeeBps(100);
        vm.prank(owner);
        forwarder.setPaymentOracle(address(paymentToken), usdcPriceOracle);
    }

    function testUpdateEthOracle(address _oracle) public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        forwarder.setEthUsdOracle(_oracle);

        vm.expectEmit(true, true, true, true);
        emit EthUsdOracleSet(_oracle);
        vm.prank(owner);
        forwarder.setEthUsdOracle(_oracle);
    }

    function testUpdateOracle(address _paymentToken, address _oracle) public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        forwarder.setPaymentOracle(_paymentToken, _oracle);

        vm.expectEmit(true, true, true, true);
        emit PaymentOracleSet(_paymentToken, _oracle);
        vm.prank(owner);
        forwarder.setPaymentOracle(_paymentToken, _oracle);
    }

    function testDeployment(uint256 cancellationCost) public {
        assertEq(forwarder.owner(), owner);
        assertEq(forwarder.feeBps(), 100);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        forwarder.setFeeBps(200);

        vm.expectEmit(true, true, true, true);
        emit FeeUpdated(100);
        vm.prank(owner);
        forwarder.setFeeBps(100);

        bytes32 domainSeparator = forwarder.DOMAIN_SEPARATOR();
        assert(domainSeparator != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        forwarder.setCancellationGasCost(cancellationCost);
        vm.expectEmit(true, true, true, true);
        emit CancellationGasCostUpdated(cancellationCost);
        vm.prank(owner);
        forwarder.setCancellationGasCost(cancellationCost);
    }

    function testAddProcessor(address setIssuer) public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
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
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
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
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(
            paymentSigUtils,
            address(paymentToken),
            quantityIn + 10 ** paymentToken.decimals(), // assume network fee < 1 usdc
            user,
            userPrivateKey,
            nonce
        );
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx);

        uint256 userBalanceBefore = paymentToken.balanceOf(user);
        uint256 issuerBalanceBefore = paymentToken.balanceOf(address(issuer));

        // 1. Request order
        vm.expectEmit(true, true, true, true);
        emit OrderRequested(0, user, order);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        assertEq(uint8(issuer.getOrderStatus(0)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(0), dummyOrder.paymentTokenQuantity);
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
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx);

        uint256 totalGasCostInWei = (gasleft() + forwarder.cancellationGasCost()) * tx.gasprice;

        // 1. Request order
        vm.expectEmit(true, true, true, false);
        // emit doesn't check data, just event has been emit
        emit UserOperationSponsored(
            metaTx.user,
            order.paymentToken,
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
            prepareForwardRequest(user, address(issuer), dataRequest, nonce, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx1);

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

        bytes memory dataCancel = abi.encodeWithSelector(issuer.requestCancel.selector, 0);
        IForwarder.ForwardRequest memory metaTx2 =
            prepareForwardRequest(user, address(issuer), dataCancel, nonce, userPrivateKey);
        multicalldata = new bytes[](1);
        multicalldata[0] = abi.encodeWithSelector(forwarder.forwardRequestCancel.selector, metaTx2);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        // there is no payment for cancellation order
        assertEq(IERC20(address(paymentToken)).balanceOf(address(user)), balanceUserBeforeCancel);
    }

    function testRescueERC20(uint256 amount, address to) public {
        vm.assume(to != address(0) && to != address(forwarder));

        MockToken paymentTokenToRescue = new MockToken("RescueMoney", "$");
        paymentTokenToRescue.mint(user, amount);

        vm.prank(user);
        paymentTokenToRescue.transfer(address(forwarder), amount);

        assertEq(paymentTokenToRescue.balanceOf(address(forwarder)), amount);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        forwarder.rescueERC20(IERC20(address(paymentTokenToRescue)), to, amount);

        vm.prank(owner);
        forwarder.rescueERC20(IERC20(address(paymentTokenToRescue)), to, amount);

        assertEq(paymentTokenToRescue.balanceOf(address(forwarder)), 0);
        assertEq(paymentTokenToRescue.balanceOf(to), amount);
    }

    function testHash() public {
        IForwarder.ForwardRequest memory metaTx1 =
            IForwarder.ForwardRequest(user, address(issuer), "0x", uint64(block.timestamp + 20 days), 0, "0x");

        bytes32 hashRequest = keccak256(
            abi.encode(
                FORWARDREQUEST_TYPEHASH, user, address(issuer), keccak256("0x"), uint64(block.timestamp + 20 days), 0
            )
        );

        bytes32 _hash = forwarder.forwardRequestHash(metaTx1);

        assertEq(hashRequest, _hash);
    }

    function testSellOrderRevertSplitRecipientSet(address _splitRecipient) public {
        vm.assume(_splitRecipient != address(0));
        IOrderProcessor.Order memory order = dummyOrder;
        order.sell = true;
        order.assetTokenQuantity = dummyOrder.paymentTokenQuantity;
        order.splitRecipient = _splitRecipient;

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, order);

        uint256 nonce = 0;

        deal(address(token), user, order.assetTokenQuantity * 1e6);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](3);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] =
            preparePermitCall(shareSigUtils, address(token), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[2] = abi.encodeWithSelector(forwarder.forwardRequestSellOrder.selector, metaTx);

        vm.expectRevert(Forwarder.InvalidSplitRecipient.selector);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);
    }

    function testSellOrder(uint256 receivedAmount) public {
        vm.assume(receivedAmount > 10 ** paymentToken.decimals());

        IOrderProcessor.Order memory order = dummyOrder;
        order.sell = true;
        order.assetTokenQuantity = dummyOrder.paymentTokenQuantity;

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, order);

        uint256 nonce = 0;

        deal(address(token), user, order.assetTokenQuantity * 1e6);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](3);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] =
            preparePermitCall(shareSigUtils, address(token), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[2] = abi.encodeWithSelector(forwarder.forwardRequestSellOrder.selector, metaTx);

        uint256 issuerBalanceBefore = token.balanceOf(address(issuer));
        vm.expectEmit(true, true, true, false);
        emit OrderRequested(0, user, order);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        assertEq(uint8(issuer.getOrderStatus(0)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(0), order.assetTokenQuantity);
        assertEq(issuer.numOpenOrders(), 1);
        assertEq(token.balanceOf(address(issuer)), order.assetTokenQuantity);
        assertEq(token.balanceOf(address(issuer)), issuerBalanceBefore + order.assetTokenQuantity);
        assertEq(issuer.escrowedBalanceOf(order.assetToken, user), order.assetTokenQuantity);

        // Get forwarder modified order
        // compute payment price in wei
        {
            uint256 paymentTokenPriceInWei = _getPaymentPriceInWei();
            uint256 sellGasCostInToken =
                _tokenAmountForGas(SELL_GAS_COST * tx.gasprice, order.paymentToken, paymentTokenPriceInWei);
            uint256 fee = (sellGasCostInToken * 100) / 10000;
            order.splitAmount = sellGasCostInToken + fee;
            order.splitRecipient = relayer;
        }

        // Fill order and pay network fee from proceeds
        vm.prank(admin);
        paymentToken.mint(operator, receivedAmount);
        vm.startPrank(operator);
        paymentToken.approve(address(issuer), receivedAmount);
        issuer.fillOrder(0, order, order.assetTokenQuantity, receivedAmount);
        vm.stopPrank();
        assertLt(paymentToken.balanceOf(user), receivedAmount);
        assertGe(paymentToken.balanceOf(relayer), 0);
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
            prepareForwardRequest(user, address(directBuyIssuer), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        // test take escrow
        if (takeAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            directBuyIssuer.takeEscrow(0, order, takeAmount);
        } else if (takeAmount > order.paymentTokenQuantity) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            directBuyIssuer.takeEscrow(0, order, takeAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit EscrowTaken(0, order.recipient, takeAmount);
            vm.prank(operator);
            directBuyIssuer.takeEscrow(0, order, takeAmount);
            assertEq(paymentToken.balanceOf(operator), takeAmount);
            assertEq(directBuyIssuer.getOrderEscrow(0), order.paymentTokenQuantity - takeAmount);
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
            prepareForwardRequest(user, address(directBuyIssuer), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        vm.prank(operator);
        directBuyIssuer.takeEscrow(0, order, order.paymentTokenQuantity);

        vm.prank(operator);
        paymentToken.approve(address(directBuyIssuer), returnAmount);

        if (returnAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            directBuyIssuer.returnEscrow(0, order, returnAmount);
        } else if (returnAmount > order.paymentTokenQuantity) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            directBuyIssuer.returnEscrow(0, order, returnAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit EscrowReturned(0, order.recipient, returnAmount);
            vm.prank(operator);
            directBuyIssuer.returnEscrow(0, order, returnAmount);
            assertEq(directBuyIssuer.getOrderEscrow(0), returnAmount);
            assertEq(paymentToken.balanceOf(address(directBuyIssuer)), fees + returnAmount);
        }
    }

    function testRequestOrderNotApprovedByProcessorReverts() public {
        vm.startPrank(admin);
        issuer.revokeRole(issuer.FORWARDER_ROLE(), address(forwarder));
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        uint256 nonce = 0;

        // 4. Mint tokens
        uint256 quantityIn = dummyOrder.paymentTokenQuantity + dummyOrderFees;
        deal(address(paymentToken), user, quantityIn);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx);

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
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx);

        vm.expectRevert(Forwarder.UnsupportedCall.selector);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        dummyOrder.sell = true;

        data = abi.encodeWithSignature("requestOrder((address,address,address,uint256))", dummyOrder);

        IForwarder.ForwardRequest memory metaTx1 =
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx1);

        vm.expectRevert(Forwarder.UnsupportedCall.selector);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        dummyOrder.sell = false;
        data = abi.encodeWithSignature("requestOrder((address,address,address,uint256))", dummyOrder);

        IForwarder.ForwardRequest memory metaTx2 =
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestSellOrder.selector, metaTx2);

        vm.expectRevert(Forwarder.UnsupportedCall.selector);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        // test request cancel unsupported call
        IForwarder.ForwardRequest memory metaTx3 =
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestCancel.selector, metaTx3);

        vm.expectRevert(Forwarder.UnsupportedCall.selector);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);
    }

    function testRequestOrderRevertInvalidRelayer() public {
        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        uint256 nonce = 0;

        //Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx);

        vm.expectRevert(Forwarder.UserNotRelayer.selector);
        forwarder.multicall(multicalldata);
    }

    function testRequestOrderRevertInvalidDeadline() public {
        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        uint256 nonce = 0;

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        metaTx.deadline = 0;
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx);

        vm.expectRevert(Forwarder.ExpiredRequest.selector);
        vm.prank(relayer);
        forwarder.multicall(multicalldata);
    }

    function testRequestOrderPausedRevertThroughFordwarder(uint256 quantityIn) public {
        vm.assume(quantityIn < 100 ether);

        IOrderProcessor.Order memory order = dummyOrder;
        order.paymentTokenQuantity = quantityIn;
        vm.prank(admin);
        issuer.setOrdersPaused(true);

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        deal(address(paymentToken), user, (order.paymentTokenQuantity + dummyOrderFees) * 1e6);

        uint256 nonce = 0;

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx);

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
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        nonce += 1;
        bytes memory dataCancel = abi.encodeWithSelector(issuer.requestCancel.selector, 0);
        IForwarder.ForwardRequest memory metaTx1 =
            prepareForwardRequest(user, address(issuer), dataCancel, nonce, userPrivateKey);
        multicalldata = new bytes[](1);
        multicalldata[0] = abi.encodeWithSelector(forwarder.forwardRequestCancel.selector, metaTx1);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);
        assertEq(issuer.cancelRequested(0), true);
    }

    function testInvaldUserNonce() public {
        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        uint256 nonce = 1;

        // Mint
        deal(address(paymentToken), user, dummyOrder.paymentTokenQuantity * 1e6);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, 0);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(Nonces.InvalidAccountNonce.selector, user, 0));
        forwarder.multicall(multicalldata);

        uint256 userNonce = forwarder.nonces(user);
        assertEq(userNonce, 0);
    }

    function testRequestOrderModuleNotFound() public {
        OrderProcessor issuer1 = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl), abi.encodeCall(OrderProcessor.initialize, (admin, treasury, tokenLockCheck))
                )
            )
        );
        vm.startPrank(admin);
        issuer1.grantRole(issuer1.FORWARDER_ROLE(), address(forwarder));
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        uint256 nonce = 0;

        // Mint
        deal(address(paymentToken), user, dummyOrder.paymentTokenQuantity * 1e6);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer1), data, nonce, userPrivateKey);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx);

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
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);

        bytes memory dataCancel = abi.encodeWithSelector(issuer.requestCancel.selector, 0);
        IForwarder.ForwardRequest memory metaTx1 =
            prepareForwardRequest(relayer, address(issuer), dataCancel, nonce, userPrivateKey);
        multicalldata = new bytes[](1);
        multicalldata[0] = abi.encodeWithSelector(forwarder.forwardRequestCancel.selector, metaTx1);

        vm.expectRevert(Forwarder.InvalidSigner.selector);
        vm.prank(relayer);
        forwarder.forwardRequestCancel(metaTx1);
        assertEq(forwarder.orderSigner(0), user);
    }

    function testCancel() public {
        bytes memory data = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        uint256 nonce = 0;

        uint256 quantityIn = dummyOrder.paymentTokenQuantity + dummyOrderFees;
        uint256 userFunds = quantityIn * 1e6;
        deal(address(paymentToken), user, userFunds);

        //  Prepare ForwardRequest
        IForwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), data, nonce, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardRequestBuyOrder.selector, metaTx);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);
        // uint256 index = abi.decode(multiReturns[1], (uint256));

        uint256 balanceUserBefore = paymentToken.balanceOf(user);

        // cancel
        vm.prank(operator);
        issuer.cancelOrder(0, dummyOrder, "test");
        assertEq(paymentToken.balanceOf(address(forwarder)), 0);
        assertEq(paymentToken.balanceOf(address(issuer)), 0);
        assertLt(paymentToken.balanceOf(address(user)), userFunds);
        assertEq(paymentToken.balanceOf(address(user)), balanceUserBefore + quantityIn);
    }

    function _getPaymentPriceInWei() internal view returns (uint256) {
        address _oracle = usdcPriceOracle;
        // slither-disable-next-line unused-return
        (, int256 paymentPrice,,,) = AggregatorV3Interface(_oracle).latestRoundData();
        // slither-disable-next-line unused-return
        (, int256 ethUSDPrice,,,) = AggregatorV3Interface(ethUsdPriceOracle).latestRoundData();
        // adjust values to align decimals
        uint8 paymentPriceDecimals = AggregatorV3Interface(_oracle).decimals();
        uint8 ethUSDPriceDecimals = AggregatorV3Interface(ethUsdPriceOracle).decimals();
        if (paymentPriceDecimals > ethUSDPriceDecimals) {
            ethUSDPrice = ethUSDPrice * int256(10 ** (paymentPriceDecimals - ethUSDPriceDecimals));
        } else if (paymentPriceDecimals < ethUSDPriceDecimals) {
            paymentPrice = paymentPrice * int256(10 ** (ethUSDPriceDecimals - paymentPriceDecimals));
        }
        // compute payment price in wei
        uint256 paymentPriceInWei = PrbMath.mulDiv(uint256(paymentPrice), 1 ether, uint256(ethUSDPrice));
        return uint256(paymentPriceInWei);
    }

    function _tokenAmountForGas(uint256 gasCostInWei, address gastoken, uint256 paymentTokenPrice)
        internal
        view
        returns (uint256)
    {
        // Apply payment token price to calculate payment amount
        // Assumes payment token price includes token decimals
        uint256 paymentAmount = 0;
        try IERC20Metadata(gastoken).decimals() returns (uint8 value) {
            paymentAmount = gasCostInWei * 10 ** value / paymentTokenPrice;
        } catch {
            paymentAmount = gasCostInWei / paymentTokenPrice;
        }
        return paymentAmount;
    }

    // set Permit for user
    function preparePermitCall(
        SigUtils permitSigUtils,
        address permitToken,
        uint256 value,
        address _user,
        uint256 _privateKey,
        uint256 _nonce
    ) internal view returns (bytes memory) {
        SigUtils.Permit memory sigPermit = SigUtils.Permit({
            owner: _user,
            spender: address(forwarder),
            value: value,
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
