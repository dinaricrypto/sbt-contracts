// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/DShareFactory.sol";

contract DeployDShare is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        DShareFactory factory = DShareFactory(vm.envAddress("DSHARE_FACTORY"));
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: %s", deployer);

        vm.startBroadcast(deployerPrivateKey);

        (address dshare, address wrappedDShare) = factory.createDShare(
            deployer,
            "Stock",
            "S.d",
            "Wrapped Stock",
            "S.dw");
        console.log("DShare address: %s", dshare);
        console.log("Wrapped DShare address: %s", wrappedDShare);

        vm.stopBroadcast();
    }
}
