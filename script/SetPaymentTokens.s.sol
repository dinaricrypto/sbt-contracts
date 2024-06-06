// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";

contract SetPaymentTokens is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        OrderProcessor orderProcessor = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));

        address[1] memory paymentTokens = [vm.envAddress("USDCE")];

        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < paymentTokens.length; i++) {
            orderProcessor.removePaymentToken(paymentTokens[i]);
            // add payment token
            // orderProcessor.setPaymentToken(paymentTokens[i], bytes4(0), 1e8, 0, 1e8, 5_000);
        }

        vm.stopBroadcast();
    }
}
