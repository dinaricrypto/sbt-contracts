// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";

contract DeployDividendScript is Script {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("deployer: %s", deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        // deploy dividend airdrop
        new DividendDistribution(deployer);

        vm.stopBroadcast();
    }
}
