// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {EscrowOrderProcessor} from "../src/orders/EscrowOrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";

contract PauseProcessorsScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        EscrowOrderProcessor issuer = EscrowOrderProcessor(address(0));
        BuyUnlockedProcessor directIssuer = BuyUnlockedProcessor(address(0));

        bool pause = true;

        vm.startBroadcast(deployerPrivateKey);

        issuer.setOrdersPaused(pause);
        directIssuer.setOrdersPaused(pause);

        vm.stopBroadcast();
    }
}
