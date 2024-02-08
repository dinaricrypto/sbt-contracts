// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {Forwarder} from "../src/forwarder/Forwarder_v030.sol";

contract DeployForwarder is Script {
    struct DeployConfig {
        address deployer;
        OrderProcessor orderProcessor;
        BuyUnlockedProcessor directBuyIssuer;
        address usdc;
        address usdcOracle;
        address usdt;
        address usdtOracle;
        address ethUsdOracle;
        address relayer;
    }

    uint256 constant SELL_GAS_COST = 421502;
    uint256 constant CANCEL_GAS_COST = 64523;
    uint16 constant FORWARDER_FEE_BPS = 2000;

    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        DeployConfig memory cfg = DeployConfig({
            deployer: vm.addr(deployerPrivateKey),
            orderProcessor: OrderProcessor(vm.envAddress("ORDERPROCESSOR")),
            directBuyIssuer: BuyUnlockedProcessor(vm.envAddress("BUYUNLOCKEDPROCESSOR")),
            usdc: vm.envAddress("USDC"),
            usdcOracle: vm.envAddress("USDCORACLE"),
            usdt: vm.envAddress("USDT"),
            usdtOracle: vm.envAddress("USDTORACLE"),
            ethUsdOracle: vm.envAddress("ETHUSDORACLE"),
            relayer: vm.envAddress("RELAYER")
        });

        console.log("deployer: %s", cfg.deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        /// ------------------ forwarder ------------------

        Forwarder forwarder = new Forwarder(cfg.ethUsdOracle, SELL_GAS_COST);
        forwarder.setCancellationGasCost(CANCEL_GAS_COST);
        forwarder.setFeeBps(FORWARDER_FEE_BPS);

        forwarder.setPaymentOracle(address(cfg.usdc), cfg.usdcOracle);
        forwarder.setPaymentOracle(address(cfg.usdt), cfg.usdtOracle);

        forwarder.setSupportedModule(address(cfg.orderProcessor), true);
        forwarder.setSupportedModule(address(cfg.directBuyIssuer), true);

        forwarder.setRelayer(cfg.relayer, true);

        cfg.orderProcessor.grantRole(cfg.orderProcessor.FORWARDER_ROLE(), address(forwarder));
        cfg.directBuyIssuer.grantRole(cfg.directBuyIssuer.FORWARDER_ROLE(), address(forwarder));

        vm.stopBroadcast();
    }
}
