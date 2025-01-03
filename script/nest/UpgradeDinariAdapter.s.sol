// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../../src/plume-nest/DinariAdapterToken.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract UpgradeDinariAdapter is Script {
    function run() external {
        // load env variables
        uint256 deployKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployKey);
        DinariAdapterToken adapter = DinariAdapterToken(vm.envAddress("NESTADAPTER"));

        console.log("deployer: %s", deployer);

        // send txs as deployer
        vm.startBroadcast(deployKey);

        DinariAdapterToken adapterImpl = new DinariAdapterToken();
        adapter.upgradeToAndCall(address(adapterImpl), "");

        console.log("adapter: %s", address(adapter));

        vm.stopBroadcast();
    }
}
