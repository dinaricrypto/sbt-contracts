// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";

contract SetFees is Script {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        OrderProcessor orderProcessor = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));
        BuyUnlockedProcessor directBuyIssuer = BuyUnlockedProcessor(vm.envAddress("BUYUNLOCKEDPROCESSOR"));
        address usdc = vm.envAddress("USDC");
        // address usdce = vm.envAddress("USDCE");
        address usdt = vm.envAddress("USDT");

        OrderProcessor.FeeRates memory fees = OrderProcessor.FeeRates({
            // perOrderFeeBuy: 1e8,
            // percentageFeeRateBuy: 5_000,
            // perOrderFeeSell: 1e8,
            // percentageFeeRateSell: 5_000
            perOrderFeeBuy: 0,
            percentageFeeRateBuy: 0,
            perOrderFeeSell: 0,
            percentageFeeRateSell: 0
        });

        address userAccount = 0xAdFeB630a6aaFf7161E200088B02Cf41112f8B98;

        console.log("deployer: %s", deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        // set default fees
        // orderProcessor.setDefaultFees(usdc, fees);
        // directBuyIssuer.setDefaultFees(usdc, fees);
        // orderProcessor.setDefaultFees(usdce, fees);
        // directBuyIssuer.setDefaultFees(usdce, fees);
        // orderProcessor.setDefaultFees(usdt, fees);
        // directBuyIssuer.setDefaultFees(usdt, fees);

        // set user fees
        orderProcessor.setFees(userAccount, usdc, fees);
        directBuyIssuer.setFees(userAccount, usdc, fees);
        // orderProcessor.setFees(userAccount, usdce, fees);
        // directBuyIssuer.setFees(userAccount, usdce, fees);
        orderProcessor.setFees(userAccount, usdt, fees);
        directBuyIssuer.setFees(userAccount, usdt, fees);

        vm.stopBroadcast();
    }
}
