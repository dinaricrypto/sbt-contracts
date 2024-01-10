// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";

contract PauseProcessorsScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        OrderProcessor issuer = OrderProcessor(address(0));

        bool pause = true;

        vm.startBroadcast(deployerPrivateKey);

        issuer.setOrdersPaused(pause);

        vm.stopBroadcast();
    }
}
