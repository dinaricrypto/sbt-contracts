// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "../src/WrappedDShare.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpgradeWrappedDShareImpl is Script {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        UpgradeableBeacon wrappedDShareBeacon = UpgradeableBeacon(vm.envAddress("WRAPPEDDSHARE_BEACON"));

        console.log("deployer: %s", deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        // deploy implementation
        WrappedDShare wrappedDShareImpl = new WrappedDShare();

        // update DShare beacon
        wrappedDShareBeacon.upgradeTo(address(wrappedDShareImpl));

        vm.stopBroadcast();
    }
}
