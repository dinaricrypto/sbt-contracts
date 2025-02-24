// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../../src/plume-nest/DinariAdapterToken.sol";

contract ProcessSubmittedOrders is Script {
    function run() external {
        uint256 privateKey = vm.envUint("DEPLOY_KEY");
        address user = vm.addr(privateKey);
        DinariAdapterToken adapter = DinariAdapterToken(vm.envAddress("NESTADAPTER"));

        console.log("User: %s", user);

        vm.startBroadcast(privateKey);

        adapter.processSubmittedOrders();

        vm.stopBroadcast();
    }
}
