// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/DShare.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpgradeDShareImpl is Script {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        UpgradeableBeacon dShareBeacon = UpgradeableBeacon(vm.envAddress("DShare_BEACON"));

        DShare dShare = DShare(vm.envAddress("AAPL"));
        uint256 holdings = dShare.totalSupply();

        console.log("deployer: %s", deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        // deploy DShare implementation
        DShare dShareImpl = new DShare();

        // update DShare beacon
        dShareBeacon.upgradeTo(address(dShareImpl));

        vm.stopBroadcast();

        console.log("AAPL holdings before: %s", holdings);
        console.log("AAPL holdings after:  %s", dShare.totalSupply());
    }
}
