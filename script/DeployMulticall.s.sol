// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/common/Multicall3.sol";

contract DeployMulticall is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: %s", deployer);

        vm.startBroadcast(deployerPrivateKey);

        Multicall3 multicall = new Multicall3();
        console.log("Multicall address: %s", address(multicall));

        vm.stopBroadcast();
    }
}
