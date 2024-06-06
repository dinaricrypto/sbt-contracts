// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {DShareFactory} from "../src/DShareFactory.sol";
import {DShare} from "../src/DShare.sol";
import {ITransferRestrictor} from "../src/ITransferRestrictor.sol";

contract UpdateRestrictor is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        DShareFactory factory = DShareFactory(vm.envAddress("FACTORY"));
        address restrictor = vm.envAddress("TRANSFERRESTRICTOR");

        vm.startBroadcast(deployerPrivateKey);

        factory.setNewTransferRestrictor(restrictor);

        (address[] memory assetTokens,) = factory.getDShares();

        for (uint256 i = 0; i < assetTokens.length; i++) {
            DShare dshare = DShare(assetTokens[i]);
            if (address(dshare.transferRestrictor()) != restrictor) {
                dshare.setTransferRestrictor(ITransferRestrictor(restrictor));
            }
        }

        vm.stopBroadcast();
    }
}
