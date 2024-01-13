// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {Nonces} from "openzeppelin-contracts/contracts/utils/Nonces.sol";
import {TokenLockCheck, ITokenLockCheck} from "../../src/TokenLockCheck.sol";
import "../../src/orders/OrderProcessor.sol";
import "../utils/SigUtils.sol";
import "../utils/mocks/MockToken.sol";
import "../utils/mocks/MockDShareFactory.sol";
import "../utils/OrderSigUtils.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {FeeLib} from "../../src/common/FeeLib.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import "prb-math/Common.sol" as PrbMath;
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NumberUtils} from "../../src/common/NumberUtils.sol";

contract OrderProcessorSignedTest is Test {
    event OrderCreated(uint256 indexed id, address indexed recipient);

    event PaymentTokenOracleSet(address indexed paymentToken, address indexed oracle);
    event EthUsdOracleSet(address indexed oracle);

    error InsufficientBalance();

    OrderProcessor public issuerImpl;
    OrderProcessor public issuer;
    MockToken public paymentToken;
    MockDShareFactory public tokenFactory;
    DShare public token;

    OrderSigUtils public orderSigUtils;
    SigUtils public paymentSigUtils;
    SigUtils public shareSigUtils;
    IOrderProcessor.Order public dummyOrder;
    TokenLockCheck tokenLockCheck;

    uint24 percentageFeeRate;

    uint256 public userPrivateKey;
    uint256 public adminPrivateKey;
    uint256 flatFee;
    uint256 dummyOrderFees;

    address public user;
    address public admin;
    address constant treasury = address(4);
    address constant operator = address(3);
    address constant ethUsdPriceOracle = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address constant usdcPriceOracle = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

    uint256 constant SELL_GAS_COST = 1000000;

    bytes32 private constant ORDER_REQUEST_TYPEHASH =
        keccak256("OrderRequest(bytes32 orderHash,uint256 deadline,uint256 nonce)");

    function setUp() public {
        userPrivateKey = 0x1;
        adminPrivateKey = 0x4;
        user = vm.addr(userPrivateKey);
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
                    address(issuerImpl),
                    abi.encodeCall(OrderProcessor.initialize, (admin, treasury, tokenLockCheck, ethUsdPriceOracle))
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
        issuer.setFees(address(0), address(paymentToken), defaultFees);
        issuer.setPaymentTokenOracle(address(paymentToken), usdcPriceOracle);
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        orderSigUtils = new OrderSigUtils(issuer);
        paymentSigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());
        shareSigUtils = new SigUtils(token.DOMAIN_SEPARATOR());

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
            escrowUnlocked: false
        });
    }

    function testUpdateEthOracle(address _oracle) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), issuer.DEFAULT_ADMIN_ROLE()
            )
        );
        issuer.setEthUsdOracle(_oracle);

        vm.expectEmit(true, true, true, true);
        emit EthUsdOracleSet(_oracle);
        vm.prank(admin);
        issuer.setEthUsdOracle(_oracle);
        assertEq(issuer.ethUsdOracle(), _oracle);
    }

    function testUpdateOracle(address _paymentToken, address _oracle) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), issuer.DEFAULT_ADMIN_ROLE()
            )
        );
        issuer.setPaymentTokenOracle(_paymentToken, _oracle);

        vm.expectEmit(true, true, true, true);
        emit PaymentTokenOracleSet(_paymentToken, _oracle);
        vm.prank(admin);
        issuer.setPaymentTokenOracle(_paymentToken, _oracle);
        assertEq(issuer.paymentTokenOracle(_paymentToken), _oracle);
    }

    function testRequestOrderThroughOperator(uint256 orderAmount) public {
        vm.assume(orderAmount > 0);

        (uint256 _flatFee, uint24 _percentageFeeRate) = issuer.getFeeRatesForOrder(user, false, address(paymentToken));
        uint256 fees = FeeLib.estimateTotalFees(_flatFee, _percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));

        IOrderProcessor.Order memory order = dummyOrder;
        order.paymentTokenQuantity = orderAmount;
        uint256 quantityIn = order.paymentTokenQuantity + fees;
        deal(address(paymentToken), user, type(uint256).max);

        // Get current price eth in token
        uint256 paymentTokenPriceInWei = issuer.getTokenPriceInWei(address(paymentToken));
        assertGt(paymentTokenPriceInWei, 0);

        uint256 nonce = issuer.nonces(user);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] =
            preparePermitCall(paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(
            issuer.pullPaymentForSignedOrder.selector,
            order,
            prepareOrderRequestSignature(order, issuer.nonces(user), userPrivateKey)
        );

        uint256 orderId = issuer.nextOrderId();
        uint256 userBalanceBefore = paymentToken.balanceOf(user);
        uint256 issuerBalanceBefore = paymentToken.balanceOf(address(issuer));

        // 1. Request order
        vm.expectEmit(true, true, true, true);
        emit OrderCreated(orderId, user);
        vm.prank(operator);
        issuer.multicall(multicalldata);

        assertEq(uint8(issuer.getOrderStatus(orderId)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(orderId), order.paymentTokenQuantity);
        assertEq(issuer.numOpenOrders(), 1);

        assertEq(paymentToken.balanceOf(address(issuer)), issuerBalanceBefore + quantityIn);
        assertLt(paymentToken.balanceOf(address(user)), userBalanceBefore - quantityIn);
        assertEq(issuer.escrowedBalanceOf(order.paymentToken, user), quantityIn);
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

    function prepareOrderRequestSignature(IOrderProcessor.Order memory order, uint256 nonce, uint256 _privateKey)
        internal
        view
        returns (IOrderProcessor.Signature memory)
    {
        uint256 deadline = block.timestamp + 30 days;
        bytes32 orderRequestDigest = orderSigUtils.getOrderRequestHashToSign(order, deadline, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, orderRequestDigest);

        return IOrderProcessor.Signature({deadline: deadline, nonce: nonce, signature: abi.encodePacked(r, s, v)});
    }
}
