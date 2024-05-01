// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/orders/OrderProcessor.sol";
import "../utils/OrderSigUtils.sol";
import "../utils/SigUtils.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract DebugTest is Test {
    OrderProcessor public orderProcessor;
    OrderSigUtils public orderSigUtils;
    SigUtils public paymentSigUtils;

    address deployer;

    uint256 public operatorPrivateKey = 0x1;
    uint256 public userPrivateKey = 0x2;

    address operator;
    address user;

    address assetToken = 0xDa38961e0174A7e86153E82De6f5ECf9D2CB3b56;
    address paymentToken = 0x45bA256ED2F8225f1F18D76ba676C1373Ba7003F;

    IOrderProcessor.Order public orderTemplate;

    function setUp() public {
        orderProcessor = OrderProcessor(vm.envAddress("ORDERPROCESSOR4"));
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        deployer = vm.addr(deployerPrivateKey);

        operator = vm.addr(operatorPrivateKey);
        user = vm.addr(userPrivateKey);

        orderSigUtils = new OrderSigUtils(orderProcessor);
        paymentSigUtils = new SigUtils(IERC20Permit(paymentToken).DOMAIN_SEPARATOR());

        // devnet config
        vm.startPrank(deployer);
        orderProcessor.setOperator(operator, true);
        orderProcessor.setPaymentToken(paymentToken, bytes4(0), 1e8, 0, 1e8, 5000);
        vm.stopPrank();

        orderTemplate = IOrderProcessor.Order({
            requestTimestamp: 47,
            recipient: 0xcF86069157B0992d6d62E02C0D1384df1A7769a1,
            assetToken: assetToken,
            paymentToken: paymentToken,
            sell: false,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 0,
            price: 0,
            tif: IOrderProcessor.TIF.GTC
        });
    }

    function testPrintConfig() public view {
        console.log("OrderProcessor: %s", address(orderProcessor));
        console.log("Deployer: %s", deployer);

        console.log("Operator: %s", operator);
        console.log("User: %s", user);

        console.log("dShareFactory: %s", address(orderProcessor.dShareFactory()));
    }

    function testCreateOrderWithSignature() public {
        uint256 orderAmount = 10000000;

        (uint256 _flatFee, uint24 _percentageFeeRate) = orderProcessor.getStandardFees(false, address(paymentToken));
        uint256 fees = _flatFee + FeeLib.applyPercentageFee(_percentageFeeRate, orderAmount);

        IOrderProcessor.Order memory order = orderTemplate;
        order.paymentTokenQuantity = orderAmount;
        deal(address(paymentToken), user, type(uint256).max);

        uint256 permitNonce = 0;
        (
            IOrderProcessor.Signature memory orderSignature,
            IOrderProcessor.FeeQuote memory feeQuote,
            bytes memory feeQuoteSignature
        ) = prepareOrderRequestSignatures(order, userPrivateKey, fees, operatorPrivateKey);

        // calldata
        // bytes[] memory multicalldata = new bytes[](2);
        // multicalldata[0] = preparePermitCall(
        //     paymentSigUtils, address(paymentToken), type(uint256).max, user, userPrivateKey, permitNonce
        // );
        // multicalldata[1] = abi.encodeWithSelector(
        //     orderProcessor.createOrderWithSignature.selector, order, orderSignature, feeQuote, feeQuoteSignature
        // );

        SigUtils.Permit memory sigPermit = SigUtils.Permit({
            owner: user,
            spender: address(orderProcessor),
            value: type(uint256).max,
            nonce: permitNonce,
            deadline: block.timestamp + 30 days
        });
        bytes32 digest = paymentSigUtils.getTypedDataHash(sigPermit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        vm.prank(operator);
        orderProcessor.selfPermit(paymentToken, sigPermit.owner, sigPermit.value, sigPermit.deadline, v, r, s);

        vm.prank(operator);
        orderProcessor.createOrderWithSignature(order, orderSignature, feeQuote, feeQuoteSignature);

        // vm.prank(operator);
        // orderProcessor.multicall(multicalldata);
    }

    function prepareOrderRequestSignatures(
        IOrderProcessor.Order memory order,
        uint256 userKey,
        uint256 fee,
        uint256 operatorKey
    ) internal view returns (IOrderProcessor.Signature memory, IOrderProcessor.FeeQuote memory, bytes memory) {
        uint64 deadline = uint64(block.timestamp + 30 days);

        bytes memory orderSignature;
        {
            bytes32 orderRequestDigest = orderSigUtils.getOrderRequestHashToSign(order, deadline);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, orderRequestDigest);
            orderSignature = abi.encodePacked(r, s, v);
        }

        IOrderProcessor.FeeQuote memory feeQuote;
        bytes memory feeQuoteSignature;
        {
            uint256 orderId = orderProcessor.hashOrder(order);
            feeQuote = IOrderProcessor.FeeQuote({
                orderId: orderId,
                requester: vm.addr(userKey),
                fee: fee,
                timestamp: uint64(block.timestamp),
                deadline: deadline
            });
            bytes32 feeQuoteDigest = orderSigUtils.getOrderFeeQuoteToSign(feeQuote);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorKey, feeQuoteDigest);
            feeQuoteSignature = abi.encodePacked(r, s, v);
        }

        return (IOrderProcessor.Signature({deadline: deadline, signature: orderSignature}), feeQuote, feeQuoteSignature);
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
            spender: address(orderProcessor),
            value: value,
            nonce: _nonce,
            deadline: block.timestamp + 30 days
        });
        bytes32 digest = permitSigUtils.getTypedDataHash(sigPermit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
        return abi.encodeWithSelector(
            orderProcessor.selfPermit.selector,
            permitToken,
            sigPermit.owner,
            sigPermit.value,
            sigPermit.deadline,
            v,
            r,
            s
        );
    }
}
