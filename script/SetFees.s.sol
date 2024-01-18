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
        OrderProcessor orderProcessor = OrderProcessor(vm.envAddress("ORDER_PROCESSOR"));
        BuyUnlockedProcessor directBuyIssuer = BuyUnlockedProcessor(vm.envAddress("BUY_UNLOCKED_PROCESSOR"));
        address usdc = vm.envAddress("USDC");
        address usdce = vm.envAddress("USDCE");
        address usdt = vm.envAddress("USDT");

        OrderProcessor.FeeRates memory fees = OrderProcessor.FeeRates({
            perOrderFeeBuy: 1 ether,
            percentageFeeRateBuy: 5_000,
            perOrderFeeSell: 1 ether,
            percentageFeeRateSell: 5_000
        });

        address userAccount = address(0);

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
        orderProcessor.setFees(userAccount, usdce, fees);
        directBuyIssuer.setFees(userAccount, usdce, fees);
        orderProcessor.setFees(userAccount, usdt, fees);
        directBuyIssuer.setFees(userAccount, usdt, fees);

        vm.stopBroadcast();
    }
}
