// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {DShare} from "../src/DShare.sol";

contract AddTokensScript is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        OrderProcessor issuer = OrderProcessor(vm.envAddress("ISSUER"));
        BuyUnlockedProcessor directIssuer = BuyUnlockedProcessor(vm.envAddress("UNLOCKED_ISSUER"));

        address[1] memory paymentTokens = [
            0x45bA256ED2F8225f1F18D76ba676C1373Ba7003F // fake USDC
        ];

        address[5] memory assetTokens = [
            0xBCf1c387ced4655DdFB19Ea9599B19d4077f202D,
            0x1128E84D3Feae1FAb65c36508bCA6E1FA55a7172,
            0xd75870ab648E5158E07Fe0A3141AbcBd4Ac329aa,
            0x54c0f59d9a8CF63423A7137e6bcD8e9bA169216e,
            0x0c55e03b976a57B13Bf7Faa592e5df367c57f1F1
        ];

        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < paymentTokens.length; i++) {
            issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), paymentTokens[i]);
            directIssuer.grantRole(directIssuer.PAYMENTTOKEN_ROLE(), paymentTokens[i]);
        }

        for (uint256 i = 0; i < assetTokens.length; i++) {
            issuer.grantRole(issuer.ASSETTOKEN_ROLE(), assetTokens[i]);
            directIssuer.grantRole(directIssuer.ASSETTOKEN_ROLE(), assetTokens[i]);

            DShare assetToken = DShare(assetTokens[i]);
            assetToken.grantRole(assetToken.MINTER_ROLE(), address(issuer));
            assetToken.grantRole(assetToken.BURNER_ROLE(), address(issuer));
            assetToken.grantRole(assetToken.MINTER_ROLE(), address(directIssuer));
        }

        vm.stopBroadcast();
    }
}
