// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import "./utils/SigUtils.sol";
import "./utils/mocks/MockToken.sol";
import "./utils/mocks/GetMockDShareFactory.sol";
import "./utils/OrderSigUtils.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {FeeLib} from "../src/common/FeeLib.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import "prb-math/Common.sol" as PrbMath;
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NumberUtils} from "../src/common/NumberUtils.sol";
import {ERC1271WalletMock} from "openzeppelin-contracts/contracts/mocks/ERC1271WalletMock.sol";

contract OrderProcessorSignedTest is Test {
    using GetMockDShareFactory for DShareFactory;

    event OrderCreated(
        uint256 indexed id, address indexed recipient, IOrderProcessor.Order order, uint256 feesEscrowed
    );

    error QuoteMismatch();
    error InvalidSignature();

    OrderProcessor public issuer;
    MockToken public paymentToken;
    DShareFactory public tokenFactory;
    DShare public token;
    ERC1271WalletMock public smartWallet;

    OrderSigUtils public orderSigUtils;
    SigUtils public paymentSigUtils;
    SigUtils public shareSigUtils;
    IOrderProcessor.Order public dummyOrder;

    // Hardcoded function selectors for createOrderWithSignature
    bytes4 constant CREATE_ORDER_4_PARAMS_SELECTOR = bytes4(
        keccak256(
            "createOrderWithSignature((uint64,address,address,address,bool,uint8,uint256,uint256,uint256,uint8),(uint64,bytes),(uint256,address,uint256,uint64,uint64),bytes)"
        )
    );
    bytes4 constant CREATE_ORDER_5_PARAMS_SELECTOR = bytes4(
        keccak256(
            "createOrderWithSignature((uint64,address,address,address,bool,uint8,uint256,uint256,uint256,uint8),(uint64,bytes),(uint256,address,uint256,uint64,uint64),bytes,address)"
        )
    );

    uint24 percentageFeeRate;
    uint256 flatFee;
    uint256 dummyOrderFees;

    uint256 public userPrivateKey;
    uint256 public adminPrivateKey;
    uint256 public operatorPrivateKey;

    address public user;
    address public admin;
    address constant treasury = address(4);
    address constant upgrader = address(5);
    address public operator;

    function setUp() public {
        userPrivateKey = 0x1;
        adminPrivateKey = 0x4;
        operatorPrivateKey = 0x3;
        user = vm.addr(userPrivateKey);
        admin = vm.addr(adminPrivateKey);
        operator = vm.addr(operatorPrivateKey);

        vm.startPrank(admin);
        (tokenFactory,,) = GetMockDShareFactory.getMockDShareFactory(admin);
        token = tokenFactory.deployDShare(admin, "Dinari Token", "dTKN");
        paymentToken = new MockToken("Money", "$");
        smartWallet = new ERC1271WalletMock(user); // Smart wallet validates signatures from user
        vm.stopPrank();

        OrderProcessor issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl),
                    abi.encodeCall(OrderProcessor.initialize, (admin, upgrader, treasury, operator, tokenFactory))
                )
            )
        );

        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), admin);
        token.grantRole(token.BURNER_ROLE(), address(issuer));
        issuer.setPaymentToken(address(paymentToken), paymentToken.isBlacklisted.selector, 1e8, 5_000, 1e8, 5_000);
        issuer.setOperator(operator, true);
        vm.stopPrank();

        orderSigUtils = new OrderSigUtils(issuer);
        paymentSigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());
        shareSigUtils = new SigUtils(token.DOMAIN_SEPARATOR());

        (flatFee, percentageFeeRate) = issuer.getStandardFees(false, address(paymentToken));
        dummyOrderFees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, 100 ether);

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

    function testRequestBuyOrderThroughOperator(uint256 orderAmount) public {
        vm.assume(orderAmount > 0);
        vm.assume(orderAmount < type(uint256).max / 2);

        (uint256 _flatFee, uint24 _percentageFeeRate) = issuer.getStandardFees(false, address(paymentToken));
        uint256 fees = _flatFee + FeeLib.applyPercentageFee(_percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));

        IOrderProcessor.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;
        uint256 quantityIn = order.paymentTokenQuantity + fees;
        deal(address(paymentToken), user, quantityIn);

        (
            IOrderProcessor.Signature memory orderSignature,
            IOrderProcessor.FeeQuote memory feeQuote,
            bytes memory feeQuoteSignature
        ) = prepareOrderRequestSignatures(order, userPrivateKey, fees, operatorPrivateKey, user);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), quantityIn, user, userPrivateKey, 0);
        multicalldata[1] =
            abi.encodeWithSelector(CREATE_ORDER_4_PARAMS_SELECTOR, order, orderSignature, feeQuote, feeQuoteSignature);

        uint256 userBalanceBefore = paymentToken.balanceOf(user);
        uint256 vaultBalanceBefore = paymentToken.balanceOf(operator);

        vm.expectEmit(true, true, true, true);
        emit OrderCreated(feeQuote.orderId, user, order, fees);
        vm.prank(operator);
        issuer.multicall(multicalldata);

        assertEq(uint8(issuer.getOrderStatus(feeQuote.orderId)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(feeQuote.orderId), order.paymentTokenQuantity);
        assertEq(paymentToken.balanceOf(operator), vaultBalanceBefore + orderAmount);
        assertEq(paymentToken.balanceOf(user), userBalanceBefore - quantityIn);
    }

    function testRequestSellOrderThroughOperator(uint256 orderAmount) public {
        vm.assume(orderAmount > 0);
        vm.assume(orderAmount < type(uint256).max);

        IOrderProcessor.Order memory order = dummyOrder;
        order.sell = true;
        order.assetTokenQuantity = orderAmount;
        order.paymentTokenQuantity = 0;
        deal(address(token), user, orderAmount);

        (
            IOrderProcessor.Signature memory orderSignature,
            IOrderProcessor.FeeQuote memory feeQuote,
            bytes memory feeQuoteSignature
        ) = prepareOrderRequestSignatures(order, userPrivateKey, 0, operatorPrivateKey, user);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(shareSigUtils, address(token), orderAmount, user, userPrivateKey, 0);
        multicalldata[1] =
            abi.encodeWithSelector(CREATE_ORDER_4_PARAMS_SELECTOR, order, orderSignature, feeQuote, feeQuoteSignature);

        uint256 orderId = issuer.hashOrder(order);
        uint256 userBalanceBefore = token.balanceOf(user);

        vm.expectEmit(true, true, true, true);
        emit OrderCreated(orderId, user, order, 0);
        vm.prank(operator);
        issuer.multicall(multicalldata);

        assertEq(uint8(issuer.getOrderStatus(orderId)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(orderId), order.assetTokenQuantity);
        assertEq(token.balanceOf(user), userBalanceBefore - orderAmount);
    }

    function testInvalidSignature(uint256 orderAmount) public {
        vm.assume(orderAmount > 0);
        vm.assume(orderAmount < type(uint256).max / 2);

        (uint256 _flatFee, uint24 _percentageFeeRate) = issuer.getStandardFees(false, address(paymentToken));
        uint256 fees = _flatFee + FeeLib.applyPercentageFee(_percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));

        IOrderProcessor.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;
        uint256 quantityIn = order.paymentTokenQuantity + fees;
        deal(address(paymentToken), user, quantityIn);

        uint256 wrongPrivateKey = 0x999;
        (
            IOrderProcessor.Signature memory orderSignature,
            IOrderProcessor.FeeQuote memory feeQuote,
            bytes memory feeQuoteSignature
        ) = prepareOrderRequestSignatures(order, wrongPrivateKey, fees, operatorPrivateKey, user);

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), quantityIn, user, userPrivateKey, 0);
        multicalldata[1] = abi.encodeWithSelector(
            CREATE_ORDER_5_PARAMS_SELECTOR, order, orderSignature, feeQuote, feeQuoteSignature, user
        );

        vm.prank(operator);
        vm.expectRevert(InvalidSignature.selector);
        issuer.multicall(multicalldata);
    }

    function testRequestBuyOrderThroughOperatorWithSmartWallet(uint256 orderAmount) public {
        vm.assume(orderAmount > 0);
        vm.assume(orderAmount < type(uint256).max / 2);

        (uint256 _flatFee, uint24 _percentageFeeRate) = issuer.getStandardFees(false, address(paymentToken));
        uint256 fees = _flatFee + FeeLib.applyPercentageFee(_percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));

        IOrderProcessor.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;
        uint256 quantityIn = order.paymentTokenQuantity + fees;
        deal(address(paymentToken), address(smartWallet), quantityIn);

        vm.prank(address(smartWallet));
        paymentToken.approve(address(issuer), quantityIn);

        (
            IOrderProcessor.Signature memory orderSignature,
            IOrderProcessor.FeeQuote memory feeQuote,
            bytes memory feeQuoteSignature
        ) = prepareOrderRequestSignatures(order, userPrivateKey, fees, operatorPrivateKey, address(smartWallet));

        bytes[] memory multicalldata = new bytes[](1);
        multicalldata[0] = abi.encodeWithSelector(
            CREATE_ORDER_5_PARAMS_SELECTOR, order, orderSignature, feeQuote, feeQuoteSignature, address(smartWallet)
        );

        uint256 smartWalletBalanceBefore = paymentToken.balanceOf(address(smartWallet));
        uint256 vaultBalanceBefore = paymentToken.balanceOf(operator);

        vm.expectEmit(true, true, true, true);
        emit OrderCreated(feeQuote.orderId, address(smartWallet), order, fees);
        vm.prank(operator);
        issuer.multicall(multicalldata);

        assertEq(uint8(issuer.getOrderStatus(feeQuote.orderId)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(feeQuote.orderId), order.paymentTokenQuantity);
        assertEq(paymentToken.balanceOf(operator), vaultBalanceBefore + orderAmount);
        assertEq(paymentToken.balanceOf(address(smartWallet)), smartWalletBalanceBefore - quantityIn);
    }

    function testQuoteMismatch(uint256 orderAmount) public {
        vm.assume(orderAmount > 0);
        vm.assume(orderAmount < type(uint256).max / 2);

        (uint256 _flatFee, uint24 _percentageFeeRate) = issuer.getStandardFees(false, address(paymentToken));
        uint256 fees = _flatFee + FeeLib.applyPercentageFee(_percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));

        IOrderProcessor.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;
        uint256 quantityIn = order.paymentTokenQuantity + fees;
        deal(address(paymentToken), user, quantityIn);

        (
            IOrderProcessor.Signature memory orderSignature,
            IOrderProcessor.FeeQuote memory feeQuote,
            bytes memory feeQuoteSignature
        ) = prepareOrderRequestSignatures(order, userPrivateKey, fees, operatorPrivateKey, user);

        IOrderProcessor.FeeQuote memory mismatchedFeeQuote = feeQuote;
        mismatchedFeeQuote.orderId = feeQuote.orderId + 1;

        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), quantityIn, user, userPrivateKey, 0);
        multicalldata[1] = abi.encodeWithSelector(
            CREATE_ORDER_5_PARAMS_SELECTOR, order, orderSignature, mismatchedFeeQuote, feeQuoteSignature, user
        );

        vm.prank(operator);
        vm.expectRevert(QuoteMismatch.selector);
        issuer.multicall(multicalldata);
    }

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
            spender: address(issuer),
            value: value,
            nonce: _nonce,
            deadline: block.timestamp + 30 days
        });
        bytes32 digest = permitSigUtils.getTypedDataHash(sigPermit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
        return abi.encodeWithSelector(
            issuer.selfPermit.selector, permitToken, sigPermit.owner, sigPermit.value, sigPermit.deadline, v, r, s
        );
    }

    function prepareFeeQuote(
        IOrderProcessor.Order memory order,
        uint256 userKey,
        uint256 fee,
        uint256 operatorKey,
        address requester
    ) internal view returns (IOrderProcessor.FeeQuote memory, bytes memory) {
        uint64 deadline = uint64(block.timestamp + 30 days);
        uint256 orderId = issuer.hashOrder(order);
        IOrderProcessor.FeeQuote memory feeQuote = IOrderProcessor.FeeQuote({
            orderId: orderId,
            requester: requester,
            fee: fee,
            timestamp: uint64(block.timestamp),
            deadline: deadline
        });

        bytes32 feeQuoteDigest = orderSigUtils.getOrderFeeQuoteToSign(feeQuote);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorKey, feeQuoteDigest);
        bytes memory feeQuoteSignature = abi.encodePacked(r, s, v);

        return (feeQuote, feeQuoteSignature);
    }

    function prepareOrderRequestSignatures(
        IOrderProcessor.Order memory order,
        uint256 userKey,
        uint256 fee,
        uint256 operatorKey,
        address requester
    ) internal view returns (IOrderProcessor.Signature memory, IOrderProcessor.FeeQuote memory, bytes memory) {
        uint64 deadline = uint64(block.timestamp + 30 days);

        bytes memory orderSignature;
        {
            bytes32 orderRequestDigest = orderSigUtils.getOrderRequestHashToSign(order, deadline);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, orderRequestDigest);
            orderSignature = abi.encodePacked(r, s, v);
        }

        (IOrderProcessor.FeeQuote memory feeQuote, bytes memory feeQuoteSignature) =
            prepareFeeQuote(order, userKey, fee, operatorKey, requester);

        return (IOrderProcessor.Signature({deadline: deadline, signature: orderSignature}), feeQuote, feeQuoteSignature);
    }
}
