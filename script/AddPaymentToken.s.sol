// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {DShare} from "../src/DShare.sol";

contract AddPaymentToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        OrderProcessor issuer = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));
        address usdc = vm.envAddress("USDC");

        console.log("deployer: %s", deployer);

        vm.startBroadcast(deployerPrivateKey);

        issuer.setPaymentToken(address(usdc), bytes4(0), 1e8, 5_000, 1e8, 5_000);

        vm.stopBroadcast();
    }
}
