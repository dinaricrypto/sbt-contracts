// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {DShareFactory} from "../src/DShareFactory.sol";
import {DShare} from "../src/DShare.sol";

contract AnnounceExistingDShare is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        DShareFactory factory = DShareFactory(vm.envAddress("FACTORY"));

        address dshare = 0x9dA913f4DCa9B210a232d588113047685a4ed4B1; // BRK.A.d
        address wrappedDshare = 0x0C39B0146F774FE4aEBC62E1dDDE7AA03A3534f1; // BRK.A.dw

        vm.startBroadcast(deployerPrivateKey);

        // assumes roles are already set
        factory.announceExistingDShare(dshare, wrappedDshare);

        vm.stopBroadcast();
    }
}
