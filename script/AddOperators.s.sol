// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {MarketBuyProcessor} from "../src/issuer/MarketBuyProcessor.sol";
import {MarketSellProcessor} from "../src/issuer/MarketSellProcessor.sol";
import {DirectBuyIssuer} from "../src/issuer/DirectBuyIssuer.sol";

contract AddOperatorsScript is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        MarketBuyProcessor buyIssuer = MarketBuyProcessor(vm.envAddress("BUY_ISSUER"));
        MarketSellProcessor sellProcessor = MarketSellProcessor(vm.envAddress("SELL_PROCESSOR"));
        DirectBuyIssuer directIssuer = DirectBuyIssuer(vm.envAddress("DIRECT_ISSUER"));

        address[1] memory operators = [
            // add operator wallets here
            address(0)
        ];

        vm.startBroadcast(deployerPrivateKey);

        // assumes all issuers have the same role
        for (uint256 i = 0; i < operators.length; i++) {
            buyIssuer.grantRole(buyIssuer.OPERATOR_ROLE(), operators[i]);
            sellProcessor.grantRole(sellProcessor.OPERATOR_ROLE(), operators[i]);
            directIssuer.grantRole(directIssuer.OPERATOR_ROLE(), operators[i]);
        }

        vm.stopBroadcast();
    }
}
