// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {DShare} from "../src/DShare.sol";

contract DShareDeployManual is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");

        vm.startBroadcast(deployerPrivateKey);

        DShare dshare = new DShare();

        vm.stopBroadcast();
    }
}
