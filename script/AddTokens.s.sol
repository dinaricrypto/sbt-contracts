// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {BuyProcessor} from "../src/orders/BuyProcessor.sol";
import {SellProcessor} from "../src/orders/SellProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {dShare} from "../src/dShare.sol";

contract AddTokensScript is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
        BuyProcessor buyIssuer = BuyProcessor(vm.envAddress("BUY_ISSUER"));
        SellProcessor sellProcessor = SellProcessor(vm.envAddress("SELL_PROCESSOR"));
        BuyUnlockedProcessor directIssuer = BuyUnlockedProcessor(vm.envAddress("DIRECT_ISSUER"));

        // address[1] memory paymentTokens = [
        //     0x45bA256ED2F8225f1F18D76ba676C1373Ba7003F // fake USDC
        // ];

        // address[5] memory assetTokens = [
        //     0xBCf1c387ced4655DdFB19Ea9599B19d4077f202D,
        //     0x1128E84D3Feae1FAb65c36508bCA6E1FA55a7172,
        //     0xd75870ab648E5158E07Fe0A3141AbcBd4Ac329aa,
        //     0x54c0f59d9a8CF63423A7137e6bcD8e9bA169216e,
        //     0x0c55e03b976a57B13Bf7Faa592e5df367c57f1F1
        // ];

        address[13] memory removeAssetTokens = [
            0xa40c0975607BDbF7B868755E352570454b5B2e48,
            0xf67e6E9a4B62accd0Aa9DD113a7ef8a0653Bb9Cb,
            0xFdC642c9B59189710D0cac0528D2791968cf560a,
            0x6AE848Cd367aC2559abC06BdbD33bEed6B2f49d5,
            0x20f11c1aBca831E235B15A4714b544Bb968f8CDF,
            0x5a8A18673aDAA0Cd1101Eb4738C05cc6967b860f,
            0x9bd7A08cD17d10E02F596Aa760dfE397C57668b4,
            0x58A8eeC9b82CdF13090A2032235Beb9152e7eB3b,
            0x70732186F811f205c28C583096C8ae861B359CEf,
            0x1ba13cD81B018e06d7a7EaD033D5131115fE6C82,
            0x9F1f1B79163dABeDe8227429588289218A832359,
            0x2888c0aC959484e53bBC6CdaBf2b8b39486225C6,
            0x2414faE77CF726cC2287B81cf174d9828adc6636
        ];

        address[13] memory addAssetTokens = [
            0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7,
            0x8240aFFe697CdE618AD05c3c8963f5Bfe152650b,
            0x3c9f23dB4DDC5655f7be636358D319A3De1Ff0c4,
            0x8E50D11a54CFF859b202b7Fe5225353bE0646410,
            0x519062155B0591627C8A0C0958110A8C5639DcA6,
            0x77308F8B63A99b24b262D930E0218ED2f49F8475,
            0x3AD63B3C0eA6d7A093ff98fdE040baddc389EcDc,
            0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c,
            0xF1f18F765F118c3598cC54dCaC1D0e12066263Fe,
            0x5B6424769823e82A1829B0A8bcAf501bFFD90d25,
            0x36d37B6cbCA364Cf1D843efF8C2f6824491bcF81,
            0xF4BD09B048248876E39Fcf2e0CDF1aee1240a9D2,
            0x9C46e1B70d447B770Dbfc8D450543a431aF6DF3A
        ];

        vm.startBroadcast(deployerPrivateKey);

        // for (uint256 i = 0; i < paymentTokens.length; i++) {
        //     buyIssuer.grantRole(buyIssuer.PAYMENTTOKEN_ROLE(), paymentTokens[i]);
        //     sellProcessor.grantRole(sellProcessor.PAYMENTTOKEN_ROLE(), paymentTokens[i]);
        //     directIssuer.grantRole(directIssuer.PAYMENTTOKEN_ROLE(), paymentTokens[i]);
        // }

        for (uint256 i = 0; i < removeAssetTokens.length; i++) {
            if (buyIssuer.hasRole(buyIssuer.ASSETTOKEN_ROLE(), removeAssetTokens[i])) {
                buyIssuer.revokeRole(buyIssuer.ASSETTOKEN_ROLE(), removeAssetTokens[i]);
            }
            if (sellProcessor.hasRole(sellProcessor.ASSETTOKEN_ROLE(), removeAssetTokens[i])) {
                sellProcessor.revokeRole(sellProcessor.ASSETTOKEN_ROLE(), removeAssetTokens[i]);
            }
            if (directIssuer.hasRole(directIssuer.ASSETTOKEN_ROLE(), removeAssetTokens[i])) {
                directIssuer.revokeRole(directIssuer.ASSETTOKEN_ROLE(), removeAssetTokens[i]);
            }

            dShare assetToken = dShare(removeAssetTokens[i]);
            if (assetToken.hasRole(assetToken.MINTER_ROLE(), address(buyIssuer))) {
                assetToken.revokeRole(assetToken.MINTER_ROLE(), address(buyIssuer));
            }
            if (assetToken.hasRole(assetToken.BURNER_ROLE(), address(sellProcessor))) {
                assetToken.revokeRole(assetToken.BURNER_ROLE(), address(sellProcessor));
            }
            if (assetToken.hasRole(assetToken.MINTER_ROLE(), address(directIssuer))) {
                assetToken.revokeRole(assetToken.MINTER_ROLE(), address(directIssuer));
            }
        }

        // for (uint256 i = 0; i < addAssetTokens.length; i++) {
        //     buyIssuer.grantRole(buyIssuer.ASSETTOKEN_ROLE(), addAssetTokens[i]);
        //     sellProcessor.grantRole(sellProcessor.ASSETTOKEN_ROLE(), addAssetTokens[i]);
        //     directIssuer.grantRole(directIssuer.ASSETTOKEN_ROLE(), addAssetTokens[i]);

        //     dShare assetToken = dShare(addAssetTokens[i]);
        //     assetToken.grantRole(assetToken.MINTER_ROLE(), address(buyIssuer));
        //     assetToken.grantRole(assetToken.BURNER_ROLE(), address(sellProcessor));
        //     assetToken.grantRole(assetToken.MINTER_ROLE(), address(directIssuer));
        // }

        vm.stopBroadcast();
    }
}
