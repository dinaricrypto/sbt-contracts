// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {BuyOrderIssuer} from "../src/issuer/BuyOrderIssuer.sol";
import {SellOrderProcessor} from "../src/issuer/SellOrderProcessor.sol";
import {DirectBuyIssuer} from "../src/issuer/DirectBuyIssuer.sol";
import {BridgedERC20} from "../src/BridgedERC20.sol";

contract AddTokensScript is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        BuyOrderIssuer buyIssuer = BuyOrderIssuer(vm.envAddress("BUY_ISSUER"));
        SellOrderProcessor sellProcessor = SellOrderProcessor(vm.envAddress("SELL_PROCESSOR"));
        DirectBuyIssuer directIssuer = DirectBuyIssuer(vm.envAddress("DIRECT_ISSUER"));

        address[1] memory paymentTokens = [
            0x1ad40240395186ea900Cb3df6Bf5B64420CeA46D // fake USDC
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
            buyIssuer.grantRole(buyIssuer.PAYMENTTOKEN_ROLE(), paymentTokens[i]);
            sellProcessor.grantRole(sellProcessor.PAYMENTTOKEN_ROLE(), paymentTokens[i]);
            directIssuer.grantRole(directIssuer.PAYMENTTOKEN_ROLE(), paymentTokens[i]);
        }

        for (uint256 i = 0; i < assetTokens.length; i++) {
            buyIssuer.grantRole(buyIssuer.ASSETTOKEN_ROLE(), assetTokens[i]);
            sellProcessor.grantRole(sellProcessor.ASSETTOKEN_ROLE(), assetTokens[i]);
            directIssuer.grantRole(directIssuer.ASSETTOKEN_ROLE(), assetTokens[i]);

            BridgedERC20 assetToken = BridgedERC20(assetTokens[i]);
            assetToken.grantRole(assetToken.MINTER_ROLE(), address(buyIssuer));
            assetToken.grantRole(assetToken.BURNER_ROLE(), address(sellProcessor));
            assetToken.grantRole(assetToken.MINTER_ROLE(), address(directIssuer));
        }

        vm.stopBroadcast();
    }
}
