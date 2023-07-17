// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {DividendAirdrop} from "../src/dividend/DividendAirdrop.sol";

contract DeployAirdropScript is Script {
    uint256 constant _CLAIM_WINDOW = 90 days;

    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address usdc = vm.envAddress("USDC");

        console.log("deployer: %s", deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        // deploy dividend airdrop
        new DividendAirdrop(usdc, _CLAIM_WINDOW);

        vm.stopBroadcast();
    }
}
