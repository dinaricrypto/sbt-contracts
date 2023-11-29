// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {EscrowOrderProcessor} from "../src/orders/EscrowOrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";

contract SetFeesScript is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        EscrowOrderProcessor issuer = EscrowOrderProcessor(vm.envAddress("ISSUER"));
        BuyUnlockedProcessor directIssuer = BuyUnlockedProcessor(vm.envAddress("DIRECT_ISSUER"));

        uint24 percentageFeeRate = 0;

        vm.startBroadcast(deployerPrivateKey);

        issuer.setFees(issuer.perOrderFee(), percentageFeeRate);
        directIssuer.setFees(directIssuer.perOrderFee(), percentageFeeRate);

        vm.stopBroadcast();
    }
}
