// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {ForwarderPyth} from "../src/forwarder/ForwarderPyth.sol";

contract AddPaymentTokens is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        OrderProcessor orderProcessor = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));
        BuyUnlockedProcessor buyUnlockedProcessor = BuyUnlockedProcessor(vm.envAddress("BUYUNLOCKEDPROCESSOR"));
        ForwarderPyth forwarder = ForwarderPyth(vm.envAddress("FORWARDER"));

        address[1] memory paymentTokens = [vm.envAddress("USDB")];

        bytes32[1] memory paymentTokenOracleIds = [bytes32(uint256(1))];
        assert(paymentTokens.length == paymentTokenOracleIds.length);

        vm.startBroadcast(deployerPrivateKey);

        OrderProcessor.FeeRates memory defaultFees = OrderProcessor.FeeRates({
            perOrderFeeBuy: 1e8,
            percentageFeeRateBuy: 0,
            perOrderFeeSell: 1e8,
            percentageFeeRateSell: 5_000
        });
        for (uint256 i = 0; i < paymentTokens.length; i++) {
            // add to order processors
            // orderProcessor.setDefaultFees(paymentTokens[i], defaultFees);
            // buyUnlockedProcessor.setDefaultFees(paymentTokens[i], defaultFees);

            // add to forwarder
            forwarder.setPaymentOracle(paymentTokens[i], bytes32(uint256(1)));
        }

        vm.stopBroadcast();
    }
}
