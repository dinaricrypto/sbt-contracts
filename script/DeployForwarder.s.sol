// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {BuyProcessor} from "../src/orders/BuyProcessor.sol";
import {SellProcessor} from "../src/orders/SellProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {TokenLockCheck, ITokenLockCheck, IERC20Usdc} from "../src/TokenLockCheck.sol";
import {Forwarder} from "../src/forwarder/Forwarder.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";

contract DeployForwarderScript is Script {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        BuyProcessor buyProcessor = BuyProcessor(vm.envAddress("BUY_ISSUER"));
        SellProcessor sellProcessor = SellProcessor(vm.envAddress("SELL_PROCESSOR"));
        BuyUnlockedProcessor directBuyProcessor = BuyUnlockedProcessor(vm.envAddress("DIRECT_ISSUER"));
        address relayer = vm.envAddress("RELAYER");
        address usdc = vm.envAddress("USDC");
        address usdce = vm.envAddress("USDCE");
        address usdt = vm.envAddress("USDT");

        console.log("deployer: %s", vm.addr(deployerPrivateKey));

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        Forwarder forwarder = new Forwarder();
        forwarder.setFeeBps(2000);
        forwarder.updateOracle(usdc, 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
        forwarder.updateOracle(usdce, 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
        forwarder.updateOracle(usdt, 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

        forwarder.setSupportedModule(address(buyProcessor), true);
        forwarder.setSupportedModule(address(sellProcessor), true);
        forwarder.setSupportedModule(address(directBuyProcessor), true);

        forwarder.setRelayer(relayer, true);

        buyProcessor.grantRole(buyProcessor.FORWARDER_ROLE(), address(forwarder));
        sellProcessor.grantRole(sellProcessor.FORWARDER_ROLE(), address(forwarder));
        directBuyProcessor.grantRole(directBuyProcessor.FORWARDER_ROLE(), address(forwarder));

        vm.stopBroadcast();
    }
}
