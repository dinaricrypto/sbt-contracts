// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";

contract AddPaymentTokens is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        OrderProcessor orderProcessor = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));

        address[1] memory paymentTokens = [vm.envAddress("USDB")];

        bytes32[1] memory paymentTokenOracleIds = [bytes32(uint256(1))];
        assert(paymentTokens.length == paymentTokenOracleIds.length);

        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < paymentTokens.length; i++) {
            // add payment token
            // orderProcessor.setPaymentTokenOracle(paymentTokens[i], paymentTokenOracleIds[i]);
            // set default fees
            orderProcessor.setFees(paymentTokens[i], 1e8, 0, 1e8, 5_000);
        }

        vm.stopBroadcast();
    }
}
