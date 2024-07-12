// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";

contract UpgradeProcessor is Script {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        OrderProcessor processor = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));

        console.log("deployer: %s", deployer);
        console.log("processor: %s", address(processor));

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        /// ------------------ order processor ------------------

        OrderProcessor orderProcessorImplementation = new OrderProcessor();
        processor.upgradeToAndCall(address(orderProcessorImplementation), "");

        vm.stopBroadcast();
    }
}
