// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {ForwarderLink} from "../src/forwarder/ForwarderLink.sol";

contract AddPaymentTokens is Script {
    uint64 constant perOrderFee = 1 ether;
    uint24 constant percentageFeeRate = 5_000;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        OrderProcessor orderProcessor = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));
        BuyUnlockedProcessor buyUnlockedProcessor = BuyUnlockedProcessor(vm.envAddress("BUYUNLOCKEDPROCESSOR"));
        ForwarderLink forwarder = ForwarderLink(vm.envAddress("FORWARDER"));

        address[1] memory paymentTokens = [vm.envAddress("USDPLUS")];

        address[1] memory paymentTokenOracles = [vm.envAddress("USDPLUSORACLE")];
        assert(paymentTokens.length == paymentTokenOracles.length);

        vm.startBroadcast(deployerPrivateKey);

        OrderProcessor.FeeRates memory defaultFees = OrderProcessor.FeeRates({
            perOrderFeeBuy: perOrderFee,
            percentageFeeRateBuy: percentageFeeRate,
            perOrderFeeSell: perOrderFee,
            percentageFeeRateSell: percentageFeeRate
        });
        for (uint256 i = 0; i < paymentTokens.length; i++) {
            // add to order processors
            orderProcessor.setDefaultFees(paymentTokens[i], defaultFees);
            buyUnlockedProcessor.setDefaultFees(paymentTokens[i], defaultFees);

            // add to forwarder
            forwarder.setPaymentOracle(paymentTokens[i], paymentTokenOracles[i]);
        }

        vm.stopBroadcast();
    }
}
