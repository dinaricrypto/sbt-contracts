// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "solady/test/utils/mocks/MockERC20.sol";
import {MockToken} from "../utils/mocks/MockToken.sol";
import "../utils/mocks/MockDShareFactory.sol";
import "../utils/SigUtils.sol";
import "../../src/orders/OrderProcessor.sol";
import "../../src/orders/IOrderProcessor.sol";
import {TransferRestrictor} from "../../src/TransferRestrictor.sol";
import {TokenLockCheck, ITokenLockCheck} from "../../src/TokenLockCheck.sol";
import {NumberUtils} from "../../src/common/NumberUtils.sol";
import {FeeLib} from "../../src/common/FeeLib.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract OrderProcessorTest is Test {
    event TreasurySet(address indexed treasury);
    event FeesSet(
        address indexed account,
        address indexed paymentToken,
        uint64 perOrderFeeBuy,
        uint24 percentageFeeRateBuy,
        uint64 perOrderFeeSell,
        uint24 percentageFeeRateSell
    );
    event FeesReset(address indexed account, address indexed paymentToken);
    event OrdersPaused(bool paused);
    event TokenLockCheckSet(ITokenLockCheck indexed tokenLockCheck);
    event MaxOrderDecimalsSet(address indexed assetToken, int8 decimals);

    event OrderRequested(uint256 indexed id, address indexed recipient, IOrderProcessor.Order order);
    event OrderFill(
        uint256 indexed id,
        address indexed requester,
        address paymentToken,
        address assetToken,
        uint256 fillAmount,
        uint256 receivedAmount,
        uint256 feesPaid
    );
    event OrderFulfilled(uint256 indexed id, address indexed recipient);
    event CancelRequested(uint256 indexed id, address indexed requester);
    event OrderCancelled(uint256 indexed id, address indexed recipient, string reason);

    struct FeeRates {
        uint64 perOrderFeeBuy;
        uint24 percentageFeeRateBuy;
        uint64 perOrderFeeSell;
        uint24 percentageFeeRateSell;
    }

    MockDShareFactory tokenFactory;
    DShare token;
    OrderProcessor issuer;
    MockToken paymentToken;
    SigUtils sigUtils;
    TokenLockCheck tokenLockCheck;
    TransferRestrictor restrictor;

    uint256 userPrivateKey;
    uint256 adminPrivateKey;
    address user;
    address admin;

    address constant operator = address(3);
    address constant treasury = address(4);
    address public restrictor_role = address(1);

    uint256 dummyOrderFees;

    function setUp() public {
        userPrivateKey = 0x01;
        adminPrivateKey = 0x02;
        user = vm.addr(userPrivateKey);
        admin = vm.addr(adminPrivateKey);

        vm.startPrank(admin);
        tokenFactory = new MockDShareFactory();
        token = tokenFactory.deploy("Dinari Token", "dTKN");
        paymentToken = new MockToken("Money", "$");
        sigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());

        tokenLockCheck = new TokenLockCheck(address(paymentToken), address(0));
        tokenLockCheck.setAsDShare(address(token));

        OrderProcessor issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl),
                    abi.encodeCall(OrderProcessor.initialize, (admin, treasury, operator, tokenLockCheck, address(1)))
                )
            )
        );

        token.grantRole(token.MINTER_ROLE(), admin);
        token.grantRole(token.MINTER_ROLE(), address(issuer));
        token.grantRole(token.BURNER_ROLE(), address(issuer));

        issuer.setFees(address(0), address(paymentToken), 1 ether, 5_000, 1 ether, 5_000);
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
        issuer.setMaxOrderDecimals(address(token), int8(token.decimals()));

        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getFeeRatesForOrder(user, false, address(paymentToken));
        dummyOrderFees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, 100 ether);

        restrictor = TransferRestrictor(address(token.transferRestrictor()));
        restrictor.grantRole(restrictor.RESTRICTOR_ROLE(), restrictor_role);
        vm.stopPrank();
    }

    function getDummyOrder(bool sell) internal view returns (IOrderProcessor.Order memory) {
        return IOrderProcessor.Order({
            recipient: user,
            assetToken: address(token),
            paymentToken: address(paymentToken),
            sell: sell,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: sell ? 100 ether : 0,
            paymentTokenQuantity: sell ? 0 : 100 ether,
            price: 0,
            tif: IOrderProcessor.TIF.GTC
        });
    }

    function testInitializationReverts() public {
        OrderProcessor issuerImpl = new OrderProcessor();

        vm.expectRevert(OrderProcessor.ZeroAddress.selector);
        new ERC1967Proxy(
            address(issuerImpl),
            abi.encodeCall(OrderProcessor.initialize, (admin, address(0), operator, tokenLockCheck, address(1)))
        );

        vm.expectRevert(OrderProcessor.ZeroAddress.selector);
        new ERC1967Proxy(
            address(issuerImpl),
            abi.encodeCall(OrderProcessor.initialize, (admin, treasury, address(0), tokenLockCheck, address(1)))
        );

        vm.expectRevert(OrderProcessor.ZeroAddress.selector);
        new ERC1967Proxy(
            address(issuerImpl),
            abi.encodeCall(OrderProcessor.initialize, (admin, treasury, operator, tokenLockCheck, address(0)))
        );
    }

    function testUpgrade() public {
        OrderProcessor issuerImpl = new OrderProcessor();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), issuer.DEFAULT_ADMIN_ROLE()
            )
        );
        issuer.upgradeToAndCall(address(issuerImpl), "");

        vm.prank(admin);
        issuer.upgradeToAndCall(address(issuerImpl), "");
    }

    function testSetTreasury(address account) public {
        vm.assume(account != address(0));
        vm.prank(admin);
        tokenLockCheck.setAsDShare(address(token));

        vm.expectEmit(true, true, true, true);
        emit TreasurySet(account);
        vm.prank(admin);
        issuer.setTreasury(account);
        assertEq(issuer.treasury(), account);
    }

    function testSetTreasuryZeroReverts() public {
        vm.expectRevert(OrderProcessor.ZeroAddress.selector);
        vm.prank(admin);
        issuer.setTreasury(address(0));
    }

    function testFlatFeeForOrder(uint8 tokenDecimals, uint64 perOrderFee) public {
        MockERC20 newToken = new MockERC20("Test Token", "TEST", tokenDecimals);
        if (tokenDecimals > 18) {
            vm.expectRevert(FeeLib.DecimalsTooLarge.selector);
            this.wrapFlatFeeForOrder(address(newToken), perOrderFee);
        } else {
            assertEq(
                wrapFlatFeeForOrder(address(newToken), perOrderFee), decimalAdjust(newToken.decimals(), perOrderFee)
            );
        }
    }

    function testSetDefaultFees(address testToken, uint64 perOrderFee, uint24 percentageFee, uint256 value) public {
        vm.assume(percentageFee < 1_000_000);

        vm.expectEmit(true, true, true, true);
        emit FeesSet(address(0), testToken, perOrderFee, percentageFee, perOrderFee, percentageFee);
        vm.prank(admin);
        issuer.setFees(address(0), testToken, perOrderFee, percentageFee, perOrderFee, percentageFee);
        (uint64 perOrderFeeBuy, uint24 percentageFeeRateBuy, uint64 perOrderFeeSell, uint24 percentageFeeRateSell) =
            issuer.getAccountFees(address(0), testToken);
        assertEq(perOrderFeeBuy, perOrderFee);
        assertEq(percentageFeeRateBuy, percentageFee);
        assertEq(perOrderFeeSell, perOrderFee);
        assertEq(percentageFeeRateSell, percentageFee);
        assertEq(FeeLib.percentageFeeForValue(value, percentageFeeRateBuy), mulDiv(value, percentageFee, 1_000_000));
    }

    function testSetFeesUnsupportedReverts(address account, address testToken) public {
        vm.assume(account != address(0));

        vm.expectRevert(abi.encodeWithSelector(OrderProcessor.UnsupportedToken.selector, testToken));
        vm.prank(admin);
        issuer.setFees(account, testToken, 1, 1, 1, 1);
    }

    function testSetFees(address testToken, uint64 perOrderFee, uint24 percentageFee, uint256 value) public {
        if (percentageFee >= 1_000_000) {
            vm.expectRevert(FeeLib.FeeTooLarge.selector);
            vm.prank(admin);
            issuer.setFees(user, testToken, perOrderFee, percentageFee, perOrderFee, percentageFee);
        } else {
            // set defaut fees first
            vm.prank(admin);
            issuer.setFees(address(0), testToken, perOrderFee, percentageFee, perOrderFee, percentageFee);

            FeeRates memory oldFees;
            {
                (
                    uint64 perOrderFeeBuyOld,
                    uint24 percentageFeeRateBuyOld,
                    uint64 perOrderFeeSellOld,
                    uint24 percentageFeeRateSellOld
                ) = issuer.getAccountFees(user, testToken);
                oldFees = FeeRates({
                    perOrderFeeBuy: perOrderFeeBuyOld,
                    percentageFeeRateBuy: percentageFeeRateBuyOld,
                    perOrderFeeSell: perOrderFeeSellOld,
                    percentageFeeRateSell: percentageFeeRateSellOld
                });
            }

            vm.expectEmit(true, true, true, true);
            emit FeesSet(user, testToken, perOrderFee, percentageFee, perOrderFee, percentageFee);
            vm.prank(admin);
            issuer.setFees(user, testToken, perOrderFee, percentageFee, perOrderFee, percentageFee);
            (uint64 perOrderFeeBuy, uint24 percentageFeeRateBuy, uint64 perOrderFeeSell, uint24 percentageFeeRateSell) =
                issuer.getAccountFees(user, testToken);
            assertEq(perOrderFeeBuy, perOrderFee);
            assertEq(percentageFeeRateBuy, percentageFee);
            assertEq(perOrderFeeSell, perOrderFee);
            assertEq(percentageFeeRateSell, percentageFee);
            assertEq(FeeLib.percentageFeeForValue(value, percentageFeeRateBuy), mulDiv(value, percentageFee, 1_000_000));

            // reset fees to default
            vm.expectEmit(true, true, true, true);
            emit FeesReset(user, testToken);
            vm.prank(admin);
            issuer.resetFees(user, testToken);
            (
                uint64 perOrderFeeBuyNewOld,
                uint24 percentageFeeRateBuyNewOld,
                uint64 perOrderFeeSellNewOld,
                uint24 percentageFeeRateSellNewOld
            ) = issuer.getAccountFees(user, testToken);
            assertEq(perOrderFeeBuyNewOld, oldFees.perOrderFeeBuy);
            assertEq(percentageFeeRateBuyNewOld, oldFees.percentageFeeRateBuy);
            assertEq(perOrderFeeSellNewOld, oldFees.perOrderFeeSell);
            assertEq(percentageFeeRateSellNewOld, oldFees.percentageFeeRateSell);
        }
    }

    function testSetTokenLockCheck(ITokenLockCheck _tokenLockCheck) public {
        vm.expectEmit(true, true, true, true);
        emit TokenLockCheckSet(_tokenLockCheck);
        vm.prank(admin);
        issuer.setTokenLockCheck(_tokenLockCheck);
        assertEq(address(issuer.tokenLockCheck()), address(_tokenLockCheck));
    }

    function testSetOrdersPaused(bool pause) public {
        vm.expectEmit(true, true, true, true);
        emit OrdersPaused(pause);
        vm.prank(admin);
        issuer.setOrdersPaused(pause);
        assertEq(issuer.ordersPaused(), pause);
    }

    function testRequestOrderZeroAmountReverts(bool sell) public {
        IOrderProcessor.Order memory order = getDummyOrder(sell);
        order.paymentTokenQuantity = 0;
        order.assetTokenQuantity = 0;

        vm.expectRevert(OrderProcessor.ZeroValue.selector);
        vm.prank(user);
        issuer.requestOrder(order);
    }

    function testRequestBuyOrder(uint256 orderAmount) public {
        vm.assume(orderAmount > 0);

        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getFeeRatesForOrder(user, false, address(paymentToken));
        uint256 fees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));

        IOrderProcessor.Order memory order = getDummyOrder(false);
        order.paymentTokenQuantity = orderAmount;
        uint256 quantityIn = order.paymentTokenQuantity + fees;

        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        uint256 orderId = issuer.nextOrderId();

        // balances before
        uint256 userBalanceBefore = paymentToken.balanceOf(user);
        uint256 operatorBalanceBefore = paymentToken.balanceOf(operator);
        vm.expectEmit(true, true, true, true);
        emit OrderRequested(orderId, user, order);
        vm.prank(user);
        uint256 id = issuer.requestOrder(order);
        assertEq(id, orderId);
        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(id), order.paymentTokenQuantity);
        assertEq(issuer.numOpenOrders(), 1);
        assertEq(paymentToken.balanceOf(user), userBalanceBefore - quantityIn);
        assertEq(paymentToken.balanceOf(operator), operatorBalanceBefore + orderAmount);
        assertEq(paymentToken.balanceOf(address(issuer)), fees);
    }

    function testRequestSellOrder(uint256 orderAmount) public {
        vm.assume(orderAmount > 0);

        IOrderProcessor.Order memory order = getDummyOrder(true);
        order.assetTokenQuantity = orderAmount;

        vm.prank(admin);
        token.mint(user, orderAmount);
        vm.prank(user);
        token.approve(address(issuer), orderAmount);

        // balances before
        uint256 userBalanceBefore = token.balanceOf(user);
        vm.expectEmit(true, true, true, true);
        emit OrderRequested(0, user, order);
        vm.prank(user);
        uint256 id = issuer.requestOrder(order);
        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(id), orderAmount);
        assertEq(issuer.numOpenOrders(), 1);
        assertEq(token.balanceOf(user), userBalanceBefore - orderAmount);
    }

    function testRequestOrderZeroAddressReverts(bool sell) public {
        IOrderProcessor.Order memory order = getDummyOrder(sell);
        order.recipient = address(0);

        vm.expectRevert(OrderProcessor.ZeroAddress.selector);
        vm.prank(user);
        issuer.requestOrder(order);
    }

    function testRequestOrderPausedReverts(bool sell) public {
        vm.prank(admin);
        issuer.setOrdersPaused(true);

        vm.expectRevert(OrderProcessor.Paused.selector);
        vm.prank(user);
        issuer.requestOrder(getDummyOrder(sell));
    }

    function testAssetTokenBlacklistReverts(bool sell) public {
        // restrict msg.sender
        vm.prank(restrictor_role);
        restrictor.restrict(user);

        assert(tokenLockCheck.isTransferLocked(address(token), user));
        vm.expectRevert(OrderProcessor.Blacklist.selector);
        vm.prank(user);
        issuer.requestOrder(getDummyOrder(sell));
    }

    function testPaymentTokenBlackListReverts(bool sell) public {
        vm.prank(admin);
        paymentToken.blacklist(user);
        assert(tokenLockCheck.isTransferLocked(address(paymentToken), user));

        vm.expectRevert(OrderProcessor.Blacklist.selector);
        vm.prank(user);
        issuer.requestOrder(getDummyOrder(sell));
    }

    function testRequestOrderUnsupportedPaymentReverts(bool sell) public {
        address tryPaymentToken = address(new MockToken("Money", "$"));

        IOrderProcessor.Order memory order = getDummyOrder(sell);
        order.paymentToken = tryPaymentToken;

        vm.expectRevert(abi.encodeWithSelector(OrderProcessor.UnsupportedToken.selector, tryPaymentToken));
        vm.prank(user);
        issuer.requestOrder(order);
    }

    function testRequestOrderUnsupportedAssetReverts(bool sell) public {
        address tryAssetToken = address(tokenFactory.deploy("Dinari Token", "dTKN"));

        IOrderProcessor.Order memory order = getDummyOrder(sell);
        order.assetToken = tryAssetToken;

        vm.expectRevert(abi.encodeWithSelector(OrderProcessor.UnsupportedToken.selector, tryAssetToken));
        vm.prank(user);
        issuer.requestOrder(order);
    }

    function testRequestSellOrderInvalidPrecision() public {
        uint256 orderAmount = 100000255;
        OrderProcessor.Order memory order = getDummyOrder(true);

        vm.expectEmit(true, true, true, true);
        emit MaxOrderDecimalsSet(order.assetToken, 0);
        vm.prank(admin);
        issuer.setMaxOrderDecimals(order.assetToken, 0);
        assertEq(issuer.maxOrderDecimals(order.assetToken), 0);
        order.assetTokenQuantity = orderAmount;

        vm.prank(admin);
        token.mint(user, order.assetTokenQuantity);
        vm.prank(user);
        token.approve(address(issuer), order.assetTokenQuantity);

        vm.expectRevert(OrderProcessor.InvalidPrecision.selector);
        vm.prank(user);
        issuer.requestOrder(order);

        // update OrderAmount
        order.assetTokenQuantity = 10 ** token.decimals();

        vm.prank(admin);
        token.mint(user, order.assetTokenQuantity);
        vm.prank(user);
        token.approve(address(issuer), order.assetTokenQuantity);

        vm.prank(user);
        issuer.requestOrder(order);
    }

    function testRequestBuyOrderWithPermit() public {
        IOrderProcessor.Order memory dummyOrder = getDummyOrder(false);
        uint256 quantityIn = dummyOrder.paymentTokenQuantity + dummyOrderFees;
        vm.prank(admin);
        paymentToken.mint(user, quantityIn * 1e6);

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: user,
            spender: address(issuer),
            value: quantityIn,
            nonce: 0,
            deadline: block.timestamp + 30 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            issuer.selfPermit.selector, address(paymentToken), permit.owner, permit.value, permit.deadline, v, r, s
        );
        calls[1] = abi.encodeWithSelector(OrderProcessor.requestOrder.selector, dummyOrder);

        // balances before
        uint256 userBalanceBefore = paymentToken.balanceOf(user);
        uint256 operatorBalanceBefore = paymentToken.balanceOf(operator);
        vm.expectEmit(true, true, true, true);
        emit OrderRequested(0, user, dummyOrder);
        vm.prank(user);
        issuer.multicall(calls);
        assertEq(paymentToken.nonces(user), 1);
        assertEq(paymentToken.allowance(user, address(issuer)), 0);
        assertEq(uint8(issuer.getOrderStatus(0)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(0), dummyOrder.paymentTokenQuantity);
        assertEq(issuer.numOpenOrders(), 1);
        assertEq(paymentToken.balanceOf(user), userBalanceBefore - quantityIn);
        assertEq(paymentToken.balanceOf(operator), operatorBalanceBefore + dummyOrder.paymentTokenQuantity);
    }

    function testFillBuyOrder(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount) public {
        vm.assume(orderAmount > 0);
        uint256 flatFee;
        uint256 fees;
        {
            uint24 percentageFeeRate;
            (flatFee, percentageFeeRate) = issuer.getFeeRatesForOrder(user, false, address(paymentToken));
            fees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, orderAmount);
            vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        }
        uint256 quantityIn = orderAmount + fees;

        IOrderProcessor.Order memory order = getDummyOrder(false);
        order.paymentTokenQuantity = orderAmount;

        uint256 feesEarned = 0;
        if (fillAmount > 0) {
            feesEarned = flatFee + mulDiv(fees - flatFee, fillAmount, order.paymentTokenQuantity);
        }
        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        vm.prank(user);
        uint256 id = issuer.requestOrder(order);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(id, order, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(id, order, fillAmount, receivedAmount);
        } else {
            // balances before
            uint256 userAssetBefore = token.balanceOf(user);
            vm.expectEmit(true, true, true, false);
            // since we can't capture
            emit OrderFill(id, order.recipient, order.paymentToken, order.assetToken, fillAmount, receivedAmount, 0);
            vm.prank(operator);
            issuer.fillOrder(id, order, fillAmount, receivedAmount);
            assertEq(issuer.getUnfilledAmount(id), orderAmount - fillAmount);
            // balances after
            assertEq(token.balanceOf(address(user)), userAssetBefore + receivedAmount);
            assertEq(paymentToken.balanceOf(address(issuer)), fees - feesEarned);
            assertEq(paymentToken.balanceOf(treasury), feesEarned);
            if (fillAmount == orderAmount) {
                assertEq(issuer.numOpenOrders(), 0);
                assertEq(issuer.getTotalReceived(id), 0);
                // if order is fullfilled in on time
                assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.FULFILLED));
            } else {
                assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
                assertEq(issuer.getTotalReceived(id), receivedAmount);
            }
        }
    }

    function testFillSellOrder(uint256 orderAmount, uint256 fillAmount, uint256 receivedAmount) public {
        vm.assume(orderAmount > 0);

        IOrderProcessor.Order memory order = getDummyOrder(true);
        order.assetTokenQuantity = orderAmount;

        uint256 feesEarned = 0;
        if (receivedAmount > 0) {
            (uint256 flatFee, uint24 percentageFeeRate) = issuer.getFeeRatesForOrder(user, true, address(paymentToken));
            if (receivedAmount <= flatFee) {
                feesEarned = receivedAmount;
            } else {
                feesEarned = flatFee + mulDiv18(receivedAmount - flatFee, percentageFeeRate);
            }
        }

        vm.prank(admin);
        token.mint(user, orderAmount);
        vm.prank(user);
        token.approve(address(issuer), orderAmount);

        vm.prank(user);
        uint256 id = issuer.requestOrder(order);

        vm.prank(admin);
        paymentToken.mint(operator, receivedAmount);
        vm.prank(operator);
        paymentToken.approve(address(issuer), receivedAmount);

        if (fillAmount == 0) {
            vm.expectRevert(OrderProcessor.ZeroValue.selector);
            vm.prank(operator);
            issuer.fillOrder(id, order, fillAmount, receivedAmount);
        } else if (fillAmount > orderAmount) {
            vm.expectRevert(OrderProcessor.AmountTooLarge.selector);
            vm.prank(operator);
            issuer.fillOrder(id, order, fillAmount, receivedAmount);
        } else {
            // balances before
            uint256 userPaymentBefore = paymentToken.balanceOf(user);
            uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
            vm.expectEmit(true, true, true, false);
            // since we can't capture the function var without rewritting the _fillOrderAccounting inside the test
            emit OrderFill(id, order.recipient, order.paymentToken, order.assetToken, fillAmount, receivedAmount, 0);
            vm.prank(operator);
            issuer.fillOrder(id, order, fillAmount, receivedAmount);
            assertEq(issuer.getUnfilledAmount(id), orderAmount - fillAmount);
            // balances after
            assertEq(paymentToken.balanceOf(user), userPaymentBefore + receivedAmount - feesEarned);
            assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore - receivedAmount);
            assertEq(paymentToken.balanceOf(treasury), feesEarned);
            if (fillAmount == orderAmount) {
                assertEq(issuer.numOpenOrders(), 0);
                assertEq(issuer.getTotalReceived(id), 0);
                assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.FULFILLED));
            } else {
                assertEq(issuer.getTotalReceived(id), receivedAmount);
                assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
            }
        }
    }

    function testFulfillBuyOrder(uint256 orderAmount, uint256 receivedAmount) public {
        vm.assume(orderAmount > 0);
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getFeeRatesForOrder(user, false, address(paymentToken));
        uint256 fees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderProcessor.Order memory order = getDummyOrder(false);
        order.paymentTokenQuantity = orderAmount;

        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        vm.prank(user);
        uint256 id = issuer.requestOrder(order);

        // balances before
        uint256 userAssetBefore = token.balanceOf(user);
        uint256 treasuryPaymentBefore = paymentToken.balanceOf(treasury);
        vm.expectEmit(true, true, true, true);
        emit OrderFulfilled(id, order.recipient);
        vm.prank(operator);
        issuer.fillOrder(id, order, orderAmount, receivedAmount);
        assertEq(issuer.getUnfilledAmount(id), 0);
        assertEq(issuer.numOpenOrders(), 0);
        assertEq(issuer.getTotalReceived(id), 0);
        // balances after
        assertEq(token.balanceOf(address(user)), userAssetBefore + receivedAmount);
        assertEq(paymentToken.balanceOf(treasury), treasuryPaymentBefore + fees);
        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.FULFILLED));
    }

    function testFulfillSellOrder(
        uint256 orderAmount,
        uint256 firstFillAmount,
        uint256 firstReceivedAmount,
        uint256 receivedAmount
    ) public {
        vm.assume(orderAmount > 0);
        vm.assume(firstFillAmount > 0);
        vm.assume(firstFillAmount <= orderAmount);
        vm.assume(firstReceivedAmount <= receivedAmount);

        IOrderProcessor.Order memory order = getDummyOrder(true);
        order.assetTokenQuantity = orderAmount;

        vm.prank(admin);
        token.mint(user, orderAmount);
        vm.prank(user);
        token.approve(address(issuer), orderAmount);

        vm.prank(user);
        uint256 id = issuer.requestOrder(order);

        vm.prank(admin);
        paymentToken.mint(operator, receivedAmount);
        vm.prank(operator);
        paymentToken.approve(address(issuer), receivedAmount);

        uint256 feesEarned = 0;
        if (receivedAmount > 0) {
            (uint256 flatFee, uint24 percentageFeeRate) = issuer.getFeeRatesForOrder(user, true, address(paymentToken));
            if (receivedAmount <= flatFee) {
                feesEarned = receivedAmount;
            } else {
                feesEarned = flatFee + mulDiv18(receivedAmount - flatFee, percentageFeeRate);
            }
        }

        // balances before
        uint256 userPaymentBefore = paymentToken.balanceOf(user);
        uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
        if (firstFillAmount < orderAmount) {
            uint256 secondFillAmount = orderAmount - firstFillAmount;
            uint256 secondReceivedAmount = receivedAmount - firstReceivedAmount;
            // first fill
            vm.expectEmit(true, true, true, false);
            emit OrderFill(
                id, order.recipient, order.paymentToken, order.assetToken, firstFillAmount, firstReceivedAmount, 0
            );
            vm.prank(operator);
            issuer.fillOrder(id, order, firstFillAmount, firstReceivedAmount);
            assertEq(issuer.getUnfilledAmount(id), orderAmount - firstFillAmount);
            assertEq(issuer.numOpenOrders(), 1);
            assertEq(issuer.getTotalReceived(id), firstReceivedAmount);

            // second fill
            vm.expectEmit(true, true, true, true);
            emit OrderFulfilled(id, order.recipient);
            vm.prank(operator);
            issuer.fillOrder(id, order, secondFillAmount, secondReceivedAmount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit OrderFulfilled(id, order.recipient);
            vm.prank(operator);
            issuer.fillOrder(id, order, orderAmount, receivedAmount);
        }
        // order closed
        assertEq(issuer.getUnfilledAmount(id), 0);
        assertEq(issuer.numOpenOrders(), 0);
        assertEq(issuer.getTotalReceived(id), 0);
        // balances after
        // Fees may be k - 1 (k == number of fills) off due to rounding
        assertApproxEqAbs(paymentToken.balanceOf(user), userPaymentBefore + receivedAmount - feesEarned, 1);
        assertEq(paymentToken.balanceOf(address(issuer)), 0);
        assertEq(token.balanceOf(address(issuer)), 0);
        assertEq(paymentToken.balanceOf(operator), operatorPaymentBefore - receivedAmount);
        assertApproxEqAbs(paymentToken.balanceOf(treasury), feesEarned, 1);
        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.FULFILLED));
    }

    function testFillOrderNoOrderReverts(bool sell, uint256 id) public {
        vm.expectRevert(OrderProcessor.OrderNotFound.selector);
        vm.prank(operator);
        issuer.fillOrder(id, getDummyOrder(sell), 100, 100);
    }

    function testRequestCancel() public {
        IOrderProcessor.Order memory dummyOrder = getDummyOrder(false);
        uint256 quantityIn = dummyOrder.paymentTokenQuantity + dummyOrderFees;

        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        vm.prank(user);
        uint256 id = issuer.requestOrder(dummyOrder);

        vm.expectEmit(true, true, true, true);
        emit CancelRequested(id, user);
        vm.prank(user);
        issuer.requestCancel(id);
    }

    function testRequestCancelNotRequesterReverts() public {
        IOrderProcessor.Order memory dummyOrder = getDummyOrder(false);
        uint256 quantityIn = dummyOrder.paymentTokenQuantity + dummyOrderFees;
        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        vm.prank(user);
        uint256 id = issuer.requestOrder(dummyOrder);

        vm.expectRevert(OrderProcessor.NotRequester.selector);
        issuer.requestCancel(id);

        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
    }

    function testRequestCancelNotFoundReverts(uint256 id) public {
        vm.expectRevert(OrderProcessor.OrderNotFound.selector);
        vm.prank(user);
        issuer.requestCancel(id);
    }

    function testCancelOrder(uint256 orderAmount, uint256 fillAmount, string calldata reason) public {
        vm.assume(orderAmount > 0);
        vm.assume(fillAmount < orderAmount);
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getFeeRatesForOrder(user, false, address(paymentToken));
        uint256 fees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, orderAmount);
        vm.assume(!NumberUtils.addCheckOverflow(orderAmount, fees));
        uint256 quantityIn = orderAmount + fees;

        IOrderProcessor.Order memory order = getDummyOrder(false);
        order.paymentTokenQuantity = orderAmount;

        vm.prank(admin);
        paymentToken.mint(user, quantityIn);
        vm.prank(user);
        paymentToken.approve(address(issuer), quantityIn);

        vm.prank(user);
        uint256 id = issuer.requestOrder(order);

        uint256 feesEarned = 0;
        if (fillAmount > 0) {
            feesEarned = flatFee + mulDiv(fees - flatFee, fillAmount, order.paymentTokenQuantity);
            vm.prank(operator);
            issuer.fillOrder(id, order, fillAmount, 100);
        }

        uint256 unfilledAmount = orderAmount - fillAmount;
        vm.prank(operator);
        paymentToken.approve(address(issuer), unfilledAmount);

        // balances before
        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(id, order.recipient, reason);
        vm.prank(operator);
        issuer.cancelOrder(id, order, reason);
        assertEq(paymentToken.balanceOf(address(issuer)), 0);
        assertEq(paymentToken.balanceOf(treasury), feesEarned);
        assertEq(issuer.getTotalReceived(id), 0);
        // balances after
        if (fillAmount > 0) {
            assertEq(paymentToken.balanceOf(address(user)), quantityIn - fillAmount - feesEarned);
        } else {
            assertEq(paymentToken.balanceOf(address(user)), quantityIn);
        }
        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.CANCELLED));
    }

    function testCancelOrderNotFoundReverts(uint256 id) public {
        vm.expectRevert(OrderProcessor.OrderNotFound.selector);
        vm.prank(operator);
        issuer.cancelOrder(id, getDummyOrder(false), "msg");
    }

    // ------------------ utils ------------------

    function wrapFlatFeeForOrder(address newToken, uint64 perOrderFee) public view returns (uint256) {
        return FeeLib.flatFeeForOrder(newToken, perOrderFee);
    }

    function decimalAdjust(uint8 decimals, uint256 fee) internal pure returns (uint256) {
        uint256 adjFee = fee;
        if (decimals < 18) {
            adjFee /= 10 ** (18 - decimals);
        } else if (decimals > 18) {
            adjFee *= 10 ** (decimals - 18);
        }
        return adjFee;
    }
}
