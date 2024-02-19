// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";

import {IInterchainTokenService, ITokenManagerType} from "../src/IInterchainTokenService.sol";

contract DeployTokenManagerScript is Script {
    IInterchainTokenService tokenManagerService = IInterchainTokenService(0xB5FB4BE02232B1bBA4dC8f81dc24C26980dE9e3C);
    ITokenManagerType.TokenManagerType tokenManagerType = ITokenManagerType.TokenManagerType.MINT_BURN;

    function run() external payable {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        bytes32 salt = vm.envBytes32("SALT");
        string memory destinationChain = vm.envString("DESTINATION_CHAIN");
        bytes memory params = vm.envBytes("PARAMS");
        uint256 gasValue = vm.envUint("GAS_VALUE");

        vm.startBroadcast(deployerPrivateKey);

        tokenManagerService.deployTokenManager{value: msg.value}(
            salt, destinationChain, tokenManagerType, params, gasValue
        );

        vm.stopBroadcast();
    }
}
