// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {FulfillmentRouter} from "../src/orders/FulfillmentRouter.sol";

contract AddOperators is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        FulfillmentRouter fulfillmentRouter = FulfillmentRouter(vm.envAddress("FULFILLMENT_ROUTER"));

        address[1] memory operators = [
            // add operator wallets here
            address(0)
        ];

        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < operators.length; i++) {
            fulfillmentRouter.grantRole(fulfillmentRouter.OPERATOR_ROLE(), operators[i]);
        }

        vm.stopBroadcast();
    }
}
