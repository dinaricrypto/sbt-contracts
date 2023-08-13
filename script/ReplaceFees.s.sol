// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import {MarketBuyProcessor} from "../src/issuer/MarketBuyProcessor.sol";
import {MarketSellProcessor} from "../src/issuer/MarketSellProcessor.sol";
import {MarketBuyUnlockedProcessor} from "../src/issuer/MarketBuyUnlockedProcessor.sol";

contract ReplaceFeesScript is Script {
    // This script will deploy a new IORderFees and replace existing fee contract for issuers.
    // To change the fee parameters on an active fee contract, call methods on the contract directly.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        MarketBuyProcessor buyIssuer = MarketBuyProcessor(vm.envAddress("BUY_ISSUER"));
        MarketSellProcessor sellProcessor = MarketSellProcessor(vm.envAddress("SELL_PROCESSOR"));
        MarketBuyUnlockedProcessor directIssuer = MarketBuyUnlockedProcessor(vm.envAddress("DIRECT_ISSUER"));

        vm.startBroadcast(deployerPrivateKey);

        IOrderFees orderFees = new OrderFees(deployer, 1_000_000, 5_000);

        buyIssuer.setOrderFees(orderFees);
        sellProcessor.setOrderFees(orderFees);
        directIssuer.setOrderFees(orderFees);

        vm.stopBroadcast();
    }
}
