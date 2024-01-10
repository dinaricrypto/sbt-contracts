// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "../src/orders/OrderProcessor.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract UpgradeOrderProcessor is Script {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        OrderProcessor processor = OrderProcessor(vm.envAddress("ORDER_PROCESSOR"));

        console.log("deployer: %s", deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        OrderProcessor processorImpl = new OrderProcessor();
        processor.upgradeToAndCall(address(processorImpl), "");

        vm.stopBroadcast();
    }
}
