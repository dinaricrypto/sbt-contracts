// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {Forwarder} from "../src/forwarder/Forwarder.sol";

contract DeployForwarder is Script {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        OrderProcessor orderProcessor = OrderProcessor(vm.envAddress("ORDER_PROCESSOR"));
        BuyUnlockedProcessor directBuyProcessor = BuyUnlockedProcessor(vm.envAddress("BUY_UNLOCKED_PROCESSOR"));
        address relayer = vm.envAddress("RELAYER");
        address usdc = vm.envAddress("USDC");
        address usdce = vm.envAddress("USDCE");
        address usdt = vm.envAddress("USDT");
        address ethusdoracle = vm.envAddress("ETHUSDORACLE");
        address usdcoracle = vm.envAddress("USDCORACLE");
        address usdtoracle = vm.envAddress("USDTORACLE");

        console.log("deployer: %s", vm.addr(deployerPrivateKey));

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        Forwarder forwarder = new Forwarder(ethusdoracle, 100000);
        forwarder.setFeeBps(2000);

        forwarder.setPaymentOracle(usdc, usdcoracle);
        forwarder.setPaymentOracle(usdce, usdcoracle);
        forwarder.setPaymentOracle(usdt, usdtoracle);

        forwarder.setSupportedModule(address(orderProcessor), true);
        forwarder.setSupportedModule(address(directBuyProcessor), true);

        forwarder.setRelayer(relayer, true);

        orderProcessor.grantRole(orderProcessor.FORWARDER_ROLE(), address(forwarder));
        directBuyProcessor.grantRole(directBuyProcessor.FORWARDER_ROLE(), address(forwarder));

        vm.stopBroadcast();
    }
}
