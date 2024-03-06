// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {InterchainTokenService} from "@axelar-network/interchain-token-service/contracts/InterchainTokenService.sol";
import {ITokenManagerType} from "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManagerType.sol";

contract DeployAxelarManager is Script {
    InterchainTokenService private constant INTERCHAIN_TOKEN_SERVICE =
        InterchainTokenService(0xB5FB4BE02232B1bBA4dC8f81dc24C26980dE9e3C);

    bytes32 private constant DINARI_SALT = keccak256("dinari");

    function run() external {
        assert(block.chainid == 1);

        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        string[] memory destinationChains = new string[](3);
        destinationChains[0] = ""; // Ethereum
        destinationChains[1] = "arbitrum";
        // destinationChains[2] = "blast";

        address[][] memory tokens = new address[][](3);
        // Ethereum
        tokens[0] = new address[](1);
        tokens[0][0] = 0x62Ec03C917FaCE0E6841AFdAfC166bF571E55E4F;
        // Arbitrum
        tokens[1] = new address[](1);
        tokens[1][0] = 0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c;
        // Blast
        tokens[2] = new address[](1);
        tokens[2][0] = 0xc85b6cFab89317B952dab87a8f85B8Eb130ad411;

        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < destinationChains.length; i++) {
            INTERCHAIN_TOKEN_SERVICE.deployTokenManager(
                keccak256(abi.encodePacked(DINARI_SALT, tokens[i][0])),
                destinationChains[i],
                ITokenManagerType.TokenManagerType.MINT_BURN,
                abi.encode(abi.encodePacked(deployer), tokens[i][0]),
                0
            );
        }

        vm.stopBroadcast();
    }
}
