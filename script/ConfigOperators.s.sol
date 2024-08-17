// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {FulfillmentRouter} from "../src/orders/FulfillmentRouter.sol";
import {Vault} from "../src/orders/Vault.sol";

contract ConfigOperators is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address operator1 = vm.envAddress("OPERATOR");
        address operator2 = vm.envAddress("OPERATOR2");
        OrderProcessor issuer = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));
        FulfillmentRouter fulfillmentRouter = FulfillmentRouter(vm.envAddress("FULFILLMENTROUTER"));
        Vault vault = Vault(vm.envAddress("VAULT"));

        console.log("Deployer: %s", deployer);

        vm.startBroadcast(deployerPrivateKey);

        issuer.setOperator(address(fulfillmentRouter), true);
        issuer.setOperator(operator1, true);
        issuer.setOperator(operator2, true);
        vault.grantRole(vault.OPERATOR_ROLE(), address(fulfillmentRouter));
        fulfillmentRouter.grantRole(fulfillmentRouter.OPERATOR_ROLE(), operator1);
        fulfillmentRouter.grantRole(fulfillmentRouter.OPERATOR_ROLE(), operator2);

        vm.stopBroadcast();
    }
}
