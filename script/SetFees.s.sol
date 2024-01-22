// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";

contract SetFees is Script {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        OrderProcessor orderProcessor = OrderProcessor(vm.envAddress("ORDER_PROCESSOR"));
        address usdc = vm.envAddress("USDC");
        address usdce = vm.envAddress("USDCE");
        address usdt = vm.envAddress("USDT");

        uint64 perOrderFeeBuy = 1 ether;
        uint24 percentageFeeRateBuy = 5_000;
        uint64 perOrderFeeSell = 1 ether;
        uint24 percentageFeeRateSell = 5_000;

        address userAccount = address(0);

        console.log("deployer: %s", deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        // set default fees
        // orderProcessor.setDefaultFees(usdc, fees);
        // orderProcessor.setDefaultFees(usdce, fees);
        // orderProcessor.setDefaultFees(usdt, fees);

        // set user fees
        orderProcessor.setFees(
            userAccount, usdc, perOrderFeeBuy, percentageFeeRateBuy, perOrderFeeSell, percentageFeeRateSell
        );
        orderProcessor.setFees(
            userAccount, usdce, perOrderFeeBuy, percentageFeeRateBuy, perOrderFeeSell, percentageFeeRateSell
        );
        orderProcessor.setFees(
            userAccount, usdt, perOrderFeeBuy, percentageFeeRateBuy, perOrderFeeSell, percentageFeeRateSell
        );

        vm.stopBroadcast();
    }
}
