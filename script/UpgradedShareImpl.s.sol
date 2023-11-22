// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "../src/dShare.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpgradedShareImpl is Script {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        UpgradeableBeacon dShareBeacon = UpgradeableBeacon(vm.envAddress("DSHARE_BEACON"));

        dShare dshare = dShare(vm.envAddress("AAPL"));
        uint256 holdings = dshare.totalSupply();

        console.log("deployer: %s", deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        // deploy dShare implementation
        dShare dShareImpl = new dShare();

        // update dShare beacon
        dShareBeacon.upgradeTo(address(dShareImpl));

        vm.stopBroadcast();

        console.log("AAPL holdings before: %s", holdings);
        console.log("AAPL holdings after:  %s", dshare.totalSupply());
    }
}
