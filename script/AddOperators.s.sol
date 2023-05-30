// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {SwapOrderIssuer} from "../src/SwapOrderIssuer.sol";
import {DirectBuyIssuer} from "../src/DirectBuyIssuer.sol";
import {LimitOrderIssuer} from "../src/LimitOrderIssuer.sol";

contract AddOperatorsScript is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        SwapOrderIssuer swapIssuer = SwapOrderIssuer(vm.envAddress("SWAP_ISSUER"));
        DirectBuyIssuer directIssuer = DirectBuyIssuer(vm.envAddress("DIRECT_ISSUER"));
        LimitOrderIssuer limitIssuer = LimitOrderIssuer(vm.envAddress("LIMIT_ISSUER"));

        address[1] memory operators = [
            // add operator wallets here
            address(0)
        ];

        vm.startBroadcast(deployerPrivateKey);

        // assumes all issuers have the same role
        uint256 operatorRole = swapIssuer.OPERATOR_ROLE();
        for (uint256 i = 0; i < operators.length; i++) {
            swapIssuer.grantRoles(operators[i], operatorRole);
            directIssuer.grantRoles(operators[i], operatorRole);
            limitIssuer.grantRoles(operators[i], operatorRole);
        }

        vm.stopBroadcast();
    }
}
