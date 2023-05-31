// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {BridgedERC20} from "../src/BridgedERC20.sol";
import {ITransferRestrictor} from "../src/ITransferRestrictor.sol";
import {SwapOrderIssuer} from "../src/SwapOrderIssuer.sol";
import {DirectBuyIssuer} from "../src/DirectBuyIssuer.sol";
import {LimitOrderIssuer} from "../src/LimitOrderIssuer.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployTokenListScript is Script {
    function run() external {
        // load config
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        ITransferRestrictor restrictor = ITransferRestrictor(vm.envAddress("TRANSFER_RESTRICTOR"));
        SwapOrderIssuer swapIssuer = SwapOrderIssuer(vm.envAddress("SWAP_ISSUER"));
        DirectBuyIssuer directIssuer = DirectBuyIssuer(vm.envAddress("DIRECT_ISSUER"));
        LimitOrderIssuer limitIssuer = LimitOrderIssuer(vm.envAddress("LIMIT_ISSUER"));

        // start
        vm.startBroadcast(deployerPrivateKey);

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
            BridgedERC20 token = new BridgedERC20(deployerAddress, names[i], symbols[i], "example.com", restrictor);

            // allow issuers to mint and burn
            token.setMinter(address(swapIssuer), true);
            token.setMinter(address(directIssuer), true);
            token.setMinter(address(limitIssuer), true);

            // allow orders for token on issuers
            // previously: swapIssuer.setTokenEnabled(address(token), true);
            swapIssuer.grantRoles(address(token), swapIssuer.ASSETTOKEN_ROLE());
            directIssuer.grantRoles(address(token), directIssuer.ASSETTOKEN_ROLE());
            limitIssuer.grantRoles(address(token), limitIssuer.ASSETTOKEN_ROLE());
        }

        vm.stopBroadcast();
    }
}
