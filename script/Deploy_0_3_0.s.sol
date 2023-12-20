// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {TokenLockCheck, ITokenLockCheck, IERC20Usdc} from "../src/TokenLockCheck.sol";
import {Forwarder} from "../src/forwarder/Forwarder.sol";
import {DShare} from "../src/DShare.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployScript is Script {
    // TODO: vault, fulfillment router
    struct DeployConfig {
        address deployer;
        ITokenLockCheck tokenLockCheck;
        address treasury;
        address operator;
        // address operator2;
        address usdc;
        address usdcOracle;
        address ethUsdOracle;
        address relayer;
    }

    uint64 constant perOrderFee = 1 ether;
    uint24 constant percentageFeeRate = 5_000;
    uint256 constant SELL_GAS_COST = 421502;
    uint256 constant CANCEL_GAS_COST = 64523;
    uint16 constant FORWARDER_FEE_BPS = 2000;

    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        DeployConfig memory cfg = DeployConfig({
            deployer: vm.addr(deployerPrivateKey),
            tokenLockCheck: TokenLockCheck(vm.envAddress("TOKENLOCKCHECK")),
            treasury: vm.envAddress("TREASURY"),
            operator: vm.envAddress("OPERATOR"),
            // operator2: vm.envAddress("OPERATOR2"),
            usdc: vm.envAddress("USDC"),
            usdcOracle: vm.envAddress("USDCORACLE"),
            ethUsdOracle: vm.envAddress("ETHUSDORACLE"),
            relayer: vm.envAddress("RELAYER")
        });

        console.log("deployer: %s", cfg.deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        /// ------------------ order processors ------------------

        OrderProcessor orderProcessorImpl = new OrderProcessor();
        OrderProcessor orderProcessor = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(orderProcessorImpl),
                    abi.encodeCall(OrderProcessor.initialize, (cfg.deployer, cfg.treasury, cfg.tokenLockCheck))
                )
            )
        );

        BuyUnlockedProcessor directBuyIssuerImpl = new BuyUnlockedProcessor();
        BuyUnlockedProcessor directBuyIssuer = BuyUnlockedProcessor(
            address(
                new ERC1967Proxy(
                    address(directBuyIssuerImpl),
                    abi.encodeCall(OrderProcessor.initialize, (cfg.deployer, cfg.treasury, cfg.tokenLockCheck))
                )
            )
        );

        // config operator
        orderProcessor.grantRole(orderProcessor.OPERATOR_ROLE(), cfg.operator);
        directBuyIssuer.grantRole(directBuyIssuer.OPERATOR_ROLE(), cfg.operator);
        // orderProcessor.grantRole(orderProcessor.OPERATOR_ROLE(), cfg.operator2);
        // directBuyIssuer.grantRole(directBuyIssuer.OPERATOR_ROLE(), cfg.operator2);

        // config asset token
        address[13] memory assetTokens = [
            // 0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7,
            // 0x3AD63B3C0eA6d7A093ff98fdE040baddc389EcDc,
            // 0xF4BD09B048248876E39Fcf2e0CDF1aee1240a9D2,
            // 0x9C46e1B70d447B770Dbfc8D450543a431aF6DF3A,
            // 0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c,
            // 0x5B6424769823e82A1829B0A8bcAf501bFFD90d25,
            // 0x77308F8B63A99b24b262D930E0218ED2f49F8475,
            // 0x8E50D11a54CFF859b202b7Fe5225353bE0646410,
            // 0x8240aFFe697CdE618AD05c3c8963f5Bfe152650b,
            // 0x3c9f23dB4DDC5655f7be636358D319A3De1Ff0c4,
            // 0x519062155B0591627C8A0C0958110A8C5639DcA6,
            // 0xF1f18F765F118c3598cC54dCaC1D0e12066263Fe,
            // 0x36d37B6cbCA364Cf1D843efF8C2f6824491bcF81,
            // 0x46b979440AC257151EE5a5bC9597B76386907FA1,
            // 0x67BaD479F77488f0f427584e267e66086a7Da43A,
            // 0xd8F728AdB72a46Ae2c92234AE8870D04907786C5,
            // 0x118346C2bb9d24412ed58C53bF9BB6f61A20d7Ec,
            // 0x0c29891dC5060618c779E2A45fbE4808Aa5aE6aD,
            // 0xeb0D1360A14c3b162f2974DAA5d218E0c1090146
            0x6B6F9456f6EA68fbE0ECDBa35a2812ca09027ec6,
            0x1e22A348A0a740E320FA70A5936ed5645f20E099,
            0xed12e3394e78C2B0074aa4479b556043cC84503C,
            0x690545833Cb240E49BC64EA4838819a26576134e,
            0x954E82364Bffa51Bb5d96e1e7f242f15D1Fb80dd,
            0x0422B59b7c80ff87E0564571bD4Bada669280831,
            0x930E85C59B257fc48997B3F597a92b3CAef2bFB4,
            0xbc0838eCfb952C79E7eb4d25AEF3820611E1ABfd,
            0x8D66331a76060e57E1d8Af220E535e354f13fE58,
            0x1f572c4677C9766d1B10d02DD2EC5a5B81b55Cd8,
            0x43Fa0a32064946a9bDa8af68213D0cdcc040DD4a,
            0x47A346407b0fbDDc0C6aE5229e2BB72185fCD60a,
            0x9eaD913Bb441bd28b51e515b57e302ecbFDeeC61
        ];
        for (uint256 i = 0; i < assetTokens.length; i++) {
            orderProcessor.grantRole(orderProcessor.ASSETTOKEN_ROLE(), assetTokens[i]);
            directBuyIssuer.grantRole(directBuyIssuer.ASSETTOKEN_ROLE(), assetTokens[i]);

            DShare assetToken = DShare(assetTokens[i]);
            assetToken.grantRole(assetToken.MINTER_ROLE(), address(orderProcessor));
            assetToken.grantRole(assetToken.BURNER_ROLE(), address(orderProcessor));
            assetToken.grantRole(assetToken.MINTER_ROLE(), address(directBuyIssuer));
        }

        /// ------------------ forwarder ------------------

        Forwarder forwarder = new Forwarder(cfg.ethUsdOracle, SELL_GAS_COST);
        forwarder.setCancellationGasCost(CANCEL_GAS_COST);
        forwarder.setFeeBps(FORWARDER_FEE_BPS);

        forwarder.setPaymentOracle(address(cfg.usdc), cfg.usdcOracle);

        forwarder.setSupportedModule(address(orderProcessor), true);
        forwarder.setSupportedModule(address(directBuyIssuer), true);

        forwarder.setRelayer(cfg.relayer, true);

        orderProcessor.grantRole(orderProcessor.FORWARDER_ROLE(), address(forwarder));
        directBuyIssuer.grantRole(directBuyIssuer.FORWARDER_ROLE(), address(forwarder));

        // config payment tokens
        address[1] memory paymentTokens = [cfg.usdc];

        address[1] memory paymentTokenOracles = [cfg.usdcOracle];

        OrderProcessor.FeeRates memory defaultFees = OrderProcessor.FeeRates({
            perOrderFeeBuy: perOrderFee,
            percentageFeeRateBuy: percentageFeeRate,
            perOrderFeeSell: perOrderFee,
            percentageFeeRateSell: percentageFeeRate
        });
        for (uint256 i = 0; i < paymentTokens.length; i++) {
            orderProcessor.setDefaultFees(paymentTokens[i], defaultFees);
            directBuyIssuer.setDefaultFees(paymentTokens[i], defaultFees);

            forwarder.setPaymentOracle(paymentTokens[i], paymentTokenOracles[i]);
        }

        vm.stopBroadcast();
    }
}
