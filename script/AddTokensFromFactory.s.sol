// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {DShareFactory} from "../src/DShareFactory.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {DShare} from "../src/DShare.sol";

contract AddTokens is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        DShareFactory factory = DShareFactory(vm.envAddress("FACTORY"));
        OrderProcessor issuer = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));

        (address[] memory assetTokens,) = factory.getDShares();
        bytes32 MINTER_ROLE = DShare(assetTokens[0]).MINTER_ROLE();
        bytes32 BURNER_ROLE = DShare(assetTokens[0]).BURNER_ROLE();

        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < assetTokens.length; i++) {
            // issuer.setOrderDecimalReduction(assetTokens[i], DShare(assetTokens[i]).decimals() - 9);

            DShare assetToken = DShare(assetTokens[i]);
            if (!assetToken.hasRole(MINTER_ROLE, address(issuer))) {
                assetToken.grantRole(MINTER_ROLE, address(issuer));
            }
            if (!assetToken.hasRole(BURNER_ROLE, address(issuer))) {
                assetToken.grantRole(BURNER_ROLE, address(issuer));
            }
        }

        vm.stopBroadcast();
    }
}
