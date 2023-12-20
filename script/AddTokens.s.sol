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

        address[16] memory assetTokens = [
            0xBCf1c387ced4655DdFB19Ea9599B19d4077f202D,
            0x1128E84D3Feae1FAb65c36508bCA6E1FA55a7172,
            0xd75870ab648E5158E07Fe0A3141AbcBd4Ac329aa,
            0x54c0f59d9a8CF63423A7137e6bcD8e9bA169216e,
            0x0c55e03b976a57B13Bf7Faa592e5df367c57f1F1,
            0x337EA4a24945124d6B0934e423124031A02e7dd4,
            0x115223789f2A4B4438AE550600f4DB3B9eb2d755,
            0xB5046bf7e05Cdaa769980273eAdfF380E4B3d014,
            0x41bE0b3368c4757B2EaD7f8Cc60D47fd64c12E9C,
            0xcc1f553cC4938c7F06f33BEd73323991e912D055,
            0x8b00335862D6d75BDE5DAB6b9911f6474f2b5B84,
            0xE1326241f9f30c3685F438a2F49d00A3a5412D0E,
            0x243648D75AFA4bd283E6E78487259E503C54d8d9,
            0x003728979b6d6764ca24627c7c96E498b6D1FeAD,
            0xDD54790958dcb11777a7fE61D9Ab5900BB94a21a,
            0x4E4A5E70bbdaB4B4bE333C6a072E42017B520c29
        ];

        vm.startBroadcast(deployerPrivateKey);

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
