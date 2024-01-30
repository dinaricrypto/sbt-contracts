// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/orders/OrderProcessor.sol";
import "../src/orders/BuyUnlockedProcessor.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract UpgradeOrderProcessor is Script {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        OrderProcessor processor = OrderProcessor(vm.envAddress("ORDER_PROCESSOR"));
        BuyUnlockedProcessor buyUnlockedProcessor = BuyUnlockedProcessor(vm.envAddress("BUY_UNLOCKED_PROCESSOR"));

        console.log("deployer: %s", deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        OrderProcessor processorImpl = new OrderProcessor();
        processor.upgradeToAndCall(address(processorImpl), "");

        BuyUnlockedProcessor buyUnlockedProcessorImpl = new BuyUnlockedProcessor();
        buyUnlockedProcessor.upgradeToAndCall(address(buyUnlockedProcessorImpl), "");

        vm.stopBroadcast();
    }
}
