// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {Forwarder} from "../src/forwarder/Forwarder.sol";

contract AddPaymentTokens is Script {
    uint64 constant perOrderFee = 1 ether;
    uint24 constant percentageFeeRate = 5_000;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        OrderProcessor issuer = OrderProcessor(vm.envAddress("ISSUER"));
        BuyUnlockedProcessor directIssuer = BuyUnlockedProcessor(vm.envAddress("UNLOCKED_ISSUER"));
        Forwarder forwarder = Forwarder(vm.envAddress("FORWARDER"));

        address[2] memory paymentTokens = [
            0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, // usdce
            0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9 // usdt
        ];

        address[2] memory paymentTokenOracles =
            [0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3, 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7];
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
            issuer.setDefaultFees(paymentTokens[i], defaultFees);
            directIssuer.setDefaultFees(paymentTokens[i], defaultFees);

            // add to forwarder
            forwarder.setPaymentOracle(paymentTokens[i], paymentTokenOracles[i]);
        }

        vm.stopBroadcast();
    }
}
