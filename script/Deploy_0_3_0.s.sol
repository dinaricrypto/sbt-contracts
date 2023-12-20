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
        address operator2;
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
            operator2: vm.envAddress("OPERATOR2"),
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
        orderProcessor.grantRole(orderProcessor.OPERATOR_ROLE(), cfg.operator2);
        directBuyIssuer.grantRole(directBuyIssuer.OPERATOR_ROLE(), cfg.operator2);

        // config payment tokens
        address[1] memory paymentTokens = [cfg.usdc];

        OrderProcessor.FeeRates memory defaultFees = OrderProcessor.FeeRates({
            perOrderFeeBuy: perOrderFee,
            percentageFeeRateBuy: percentageFeeRate,
            perOrderFeeSell: perOrderFee,
            percentageFeeRateSell: percentageFeeRate
        });
        for (uint256 i = 0; i < paymentTokens.length; i++) {
            orderProcessor.setDefaultFees(paymentTokens[i], defaultFees);
            directBuyIssuer.setDefaultFees(paymentTokens[i], defaultFees);
        }

        // config asset token
        address[16] memory assetTokens = [
            0xBCf1c387ced4655DdFB19Ea9599B19d4077f202D,
            0x1128E84D3Feae1FAb65c36508bCA6E1FA55a7172,
            0xd75870ab648E5158E07Fe0A3141AbcBd4Ac329aa,
            0x54c0f59d9a8CF63423A7137e6bcD8e9bA169216e,
            0x0c55e03b976a57B13Bf7Faa592e5df367c57f1F1,
            0x337EA4a24945124d6B0934e423124031A02e7dd4,
            0x115223789f2A4B4438AE550600f4DB3B9eb2d755,
            0xB5046bf7e05Cdaa769980273eAdfF380E4B3d014,
            0x41bE0b3368c4757B2EaD7f8Cc60D47fd64c12E9C,
            0xcc1f553cC4938c7F06f33BEd73323991e912D055,
            0x8b00335862D6d75BDE5DAB6b9911f6474f2b5B84,
            0xE1326241f9f30c3685F438a2F49d00A3a5412D0E,
            0x243648D75AFA4bd283E6E78487259E503C54d8d9,
            0x003728979b6d6764ca24627c7c96E498b6D1FeAD,
            0xDD54790958dcb11777a7fE61D9Ab5900BB94a21a,
            0x4E4A5E70bbdaB4B4bE333C6a072E42017B520c29
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

        vm.stopBroadcast();
    }
}
