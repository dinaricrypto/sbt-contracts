// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/orders/OrderProcessor.sol";
import {DShare} from "../src/DShare.sol";

contract SetPaymentToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        OrderProcessor issuer = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));
        address usdc = vm.envAddress("USDPLUS");

        console.log("deployer: %s", deployer);

        vm.startBroadcast(deployerPrivateKey);

        OrderProcessor.PaymentTokenConfig memory paymentTokenConfig = issuer.getPaymentTokenConfig(address(usdc));
        console.log("token enabled: %s", paymentTokenConfig.enabled);
        if (paymentTokenConfig.enabled) {
            issuer.setPaymentToken(
                address(usdc),
                paymentTokenConfig.blacklistCallSelector,
                10e8,
                paymentTokenConfig.percentageFeeRateBuy,
                10e8,
                paymentTokenConfig.percentageFeeRateSell
            );
        }

        vm.stopBroadcast();
    }
}
