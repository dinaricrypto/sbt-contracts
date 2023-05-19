// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/BridgedERC20.sol";
import "../src/ITransferRestrictor.sol";
import "../src/SwapOrderIssuer.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployTokenListScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address restrictor = vm.envAddress("TRANSFER_RESTRICTOR");
        address bridge = vm.envAddress("ISSUER");
        vm.startBroadcast(deployerPrivateKey);

        address deployerAddress = vm.addr(deployerPrivateKey);

        string[5] memory names = [
            "Decentralized Apple",
            "Decentralized Tesla",
            "Decentralized Amazon",
            "Decentralized Microsoft",
            "Decentralized Alphabet"
        ];

        string[5] memory symbols = ["dAAPL", "dTSLA", "dAMZN", "dMSFT", "dGOOGL"];

        for (uint256 i = 0; i < 5; i++) {
            // deploy token
            BridgedERC20 token =
                new BridgedERC20(deployerAddress, names[i], symbols[i], "example.com", ITransferRestrictor(restrictor));

            // allow issuer to mint and burn
            token.grantRoles(bridge, token.minterRole());

            // allow orders for token on issuer
            // previously: SwapOrderIssuer(bridge).setTokenEnabled(address(token), true);
            SwapOrderIssuer(bridge).grantRoles(address(token), SwapOrderIssuer(bridge).ASSETTOKEN_ROLE());
        }

        vm.stopBroadcast();
    }
}
