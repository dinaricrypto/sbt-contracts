// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {OrderFees, IOrderFees} from "../src/orders/OrderFees.sol";
import {BuyProcessor} from "../src/orders/BuyProcessor.sol";
import {SellProcessor} from "../src/orders/SellProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";

contract ReplaceFeesScript is Script {
    // This script will deploy a new IORderFees and replace existing fee contract for issuers.
    // To change the fee parameters on an active fee contract, call methods on the contract directly.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        BuyProcessor buyIssuer = BuyProcessor(vm.envAddress("BUY_ISSUER"));
        SellProcessor sellProcessor = SellProcessor(vm.envAddress("SELL_PROCESSOR"));
        BuyUnlockedProcessor directIssuer = BuyUnlockedProcessor(vm.envAddress("DIRECT_ISSUER"));

        vm.startBroadcast(deployerPrivateKey);

        IOrderFees orderFees = new OrderFees(deployer, 1_000_000, 5_000);

        buyIssuer.setOrderFees(orderFees);
        sellProcessor.setOrderFees(orderFees);
        directIssuer.setOrderFees(orderFees);

        vm.stopBroadcast();
    }
}
