// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {Vault} from "../src/orders/Vault.sol";
import {FulfillmentRouter} from "../src/orders/FulfillmentRouter.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";

contract DeployFillRouter is Script {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        OrderProcessor orderProcessor = OrderProcessor(vm.envAddress("ORDER_PROCESSOR"));
        BuyUnlockedProcessor buyUnlockedProcessor = BuyUnlockedProcessor(vm.envAddress("BUY_UNLOCKED_PROCESSOR"));
        address operator = vm.envAddress("OPERATOR");
        // address operator2 = vm.envAddress("OPERATOR2");

        console.log("deployer: %s", vm.addr(deployerPrivateKey));

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        // deploy fulfillment router
        FulfillmentRouter router = new FulfillmentRouter(deployer);
        // allow operator to use router
        router.grantRole(router.OPERATOR_ROLE(), operator);
        // router.grantRole(router.OPERATOR_ROLE(), operator2);
        // allow router to call order processors
        orderProcessor.grantRole(orderProcessor.OPERATOR_ROLE(), address(router));
        buyUnlockedProcessor.grantRole(buyUnlockedProcessor.OPERATOR_ROLE(), address(router));

        // deploy vault
        Vault vault = new Vault(deployer);
        // allow router to withdraw from vault
        vault.grantRole(vault.OPERATOR_ROLE(), address(router));

        vm.stopBroadcast();
    }
}
