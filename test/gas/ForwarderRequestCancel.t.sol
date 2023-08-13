// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Forwarder} from "../../src/forwarder/Forwarder.sol";
import {Nonces} from "../../src/common/Nonces.sol";
import {OrderFees, IOrderFees} from "../../src/issuer/OrderFees.sol";
import {TokenLockCheck, ITokenLockCheck} from "../../src/TokenLockCheck.sol";
import {MarketBuyProcessor, OrderProcessor} from "../../src/issuer/MarketBuyProcessor.sol";
import {MarketSellProcessor} from "../../src/issuer/MarketSellProcessor.sol";
import "../utils/SigUtils.sol";
import "../../src/issuer/IOrderProcessor.sol";
import "../utils/mocks/MockToken.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../utils/mocks/MockdShare.sol";
import "../utils/SigMeta.sol";
import "../utils/SigPrice.sol";
import "../../src/forwarder/PriceAttestationConsumer.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {FeeLib} from "../../src/FeeLib.sol";

// additional tests for gas profiling
contract ForwarderRequestCancelTest is Test {
    Forwarder public forwarder;
    MarketBuyProcessor public issuer;
    MarketSellProcessor public sellIssuer;
    OrderFees public orderFees;
    MockToken public paymentToken;
    dShare public token;

    SigMeta public sigMeta;
    SigPrice public sigPrice;
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
    // price of payment token in wei, accounting for decimals
    uint256 paymentTokenPrice;

    address public user;
    address public relayer;
    address public owner;
    address constant treasury = address(4);
    address constant operator = address(3);

    uint64 priceRecencyThreshold = 30 seconds;
    bytes dataCancel;
    PriceAttestationConsumer.PriceAttestation attestation;

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

        issuer = new MarketBuyProcessor(address(this), treasury, orderFees, tokenLockCheck);
        sellIssuer = new MarketSellProcessor(address(this), treasury, orderFees, tokenLockCheck);

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
        forwarder.setSupportedModule(address(issuer), true);
        forwarder.setTrustedOracle(relayer, true);
        forwarder.setRelayer(relayer, true);
        vm.stopPrank();

        sigMeta = new SigMeta(forwarder.DOMAIN_SEPARATOR());
        sigPrice = new SigPrice(forwarder.DOMAIN_SEPARATOR());
        paymentSigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());
        shareSigUtils = new SigUtils(token.DOMAIN_SEPARATOR());

        (flatFee, percentageFeeRate) = issuer.getFeeRatesForOrder(address(paymentToken));
        dummyOrderFees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, 100 ether);

        dummyOrder = IOrderProcessor.Order({
            recipient: user,
            index: 0,
            quantityIn: 100 ether + dummyOrderFees,
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

        uint256 fees = FeeLib.estimateTotalFees(flatFee, percentageFeeRate, dummyOrder.quantityIn);

        IOrderProcessor.Order memory order = dummyOrder;
        order.quantityIn = dummyOrder.quantityIn + fees;
        order.paymentTokenQuantity = dummyOrder.quantityIn;

        deal(address(paymentToken), user, dummyOrder.quantityIn * 1e6);

        dataCancel = abi.encodeWithSelector(issuer.requestCancel.selector, user, order.index);
        bytes memory dataRequest = abi.encodeWithSelector(issuer.requestOrder.selector, dummyOrder);

        uint256 nonce = 0;

        attestation = preparePriceAttestation();

        Forwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), dataRequest, nonce, attestation, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        // set a request
        vm.prank(relayer);
        forwarder.multicall(multicalldata);
    }

    function testRequestCancel() public {
        uint256 nonce = 1;

        Forwarder.ForwardRequest memory metaTx =
            prepareForwardRequest(user, address(issuer), dataCancel, nonce, attestation, userPrivateKey);

        // calldata
        bytes[] memory multicalldata = new bytes[](2);
        multicalldata[0] = preparePermitCall(paymentSigUtils, address(paymentToken), user, userPrivateKey, nonce);
        multicalldata[1] = abi.encodeWithSelector(forwarder.forwardFunctionCall.selector, metaTx);

        vm.prank(relayer);
        forwarder.multicall(multicalldata);
    }
    //     // utils functions

    function preparePriceAttestation() internal view returns (PriceAttestationConsumer.PriceAttestation memory) {
        SigPrice.PriceAttestation memory priceAttestation = SigPrice.PriceAttestation({
            token: address(paymentToken),
            price: paymentTokenPrice,
            timestamp: uint64(block.timestamp),
            chainId: block.chainid
        });
        bytes32 digestPrice = sigPrice.getTypedDataHashForPriceAttestation(priceAttestation);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerPrivateKey, digestPrice);
        return PriceAttestationConsumer.PriceAttestation({
            token: priceAttestation.token,
            price: priceAttestation.price,
            timestamp: priceAttestation.timestamp,
            chainId: priceAttestation.chainId,
            signature: abi.encodePacked(r, s, v)
        });
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
        PriceAttestationConsumer.PriceAttestation memory _attestation,
        uint256 _privateKey
    ) internal view returns (Forwarder.ForwardRequest memory) {
        SigMeta.ForwardRequest memory MetaTx = SigMeta.ForwardRequest({
            user: _user,
            to: to,
            data: data,
            deadline: 30 days,
            nonce: nonce,
            paymentTokenOraclePrice: _attestation
        });

        bytes32 digestMeta = sigMeta.getHashToSign(MetaTx);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(_privateKey, digestMeta);

        Forwarder.ForwardRequest memory metaTx = Forwarder.ForwardRequest({
            user: _user,
            to: to,
            data: data,
            deadline: 30 days,
            nonce: nonce,
            paymentTokenOraclePrice: _attestation,
            signature: abi.encodePacked(r2, s2, v2)
        });

        return metaTx;
    }
}
