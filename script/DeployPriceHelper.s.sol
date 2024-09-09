// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/orders/LatestPriceHelper.sol";

contract DeployPriceHelper is Script {
    function run() external {
        // load env variables
        uint256 deployKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployKey);

        console.log("deployer: %s", deployer);

        bytes32 salt = keccak256(abi.encodePacked("0.4.3"));

        // send txs as deployer
        vm.startBroadcast(deployKey);

        LatestPriceHelper latestPriceHelper = new LatestPriceHelper{salt: salt}();
        console.log("latest price helper: %s", address(latestPriceHelper));

        vm.stopBroadcast();
    }
}
