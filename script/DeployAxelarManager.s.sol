// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {InterchainTokenService} from "interchain-token-service/contracts/InterchainTokenService.sol";

contract DeployAxelarManager is Script {
    InterchainTokenService private constant InterchainTokenService =
        InterchainTokenService(0xB5FB4BE02232B1bBA4dC8f81dc24C26980dE9e3C);

    function run() external {
        assert(block.chainid == 1);

        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");

        vm.startBroadcast(deployerPrivateKey);

        vm.stopBroadcast();
    }
}
