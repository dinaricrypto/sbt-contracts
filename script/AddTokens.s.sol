// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {DShare} from "../src/DShare.sol";

contract AddTokensScript is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        OrderProcessor issuer = OrderProcessor(vm.envAddress("ISSUER"));

        address[19] memory assetTokens = [
            0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7,
            0x3AD63B3C0eA6d7A093ff98fdE040baddc389EcDc,
            0xF4BD09B048248876E39Fcf2e0CDF1aee1240a9D2,
            0x9C46e1B70d447B770Dbfc8D450543a431aF6DF3A,
            0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c,
            0x5B6424769823e82A1829B0A8bcAf501bFFD90d25,
            0x77308F8B63A99b24b262D930E0218ED2f49F8475,
            0x8E50D11a54CFF859b202b7Fe5225353bE0646410,
            0x8240aFFe697CdE618AD05c3c8963f5Bfe152650b,
            0x3c9f23dB4DDC5655f7be636358D319A3De1Ff0c4,
            0x519062155B0591627C8A0C0958110A8C5639DcA6,
            0xF1f18F765F118c3598cC54dCaC1D0e12066263Fe,
            0x36d37B6cbCA364Cf1D843efF8C2f6824491bcF81,
            0x46b979440AC257151EE5a5bC9597B76386907FA1,
            0x67BaD479F77488f0f427584e267e66086a7Da43A,
            0xd8F728AdB72a46Ae2c92234AE8870D04907786C5,
            0x118346C2bb9d24412ed58C53bF9BB6f61A20d7Ec,
            0x0c29891dC5060618c779E2A45fbE4808Aa5aE6aD,
            0xeb0D1360A14c3b162f2974DAA5d218E0c1090146
            // 0xBCf1c387ced4655DdFB19Ea9599B19d4077f202D,
            // 0x1128E84D3Feae1FAb65c36508bCA6E1FA55a7172,
            // 0xd75870ab648E5158E07Fe0A3141AbcBd4Ac329aa,
            // 0x54c0f59d9a8CF63423A7137e6bcD8e9bA169216e,
            // 0x0c55e03b976a57B13Bf7Faa592e5df367c57f1F1,
            // 0x337EA4a24945124d6B0934e423124031A02e7dd4,
            // 0x115223789f2A4B4438AE550600f4DB3B9eb2d755,
            // 0xB5046bf7e05Cdaa769980273eAdfF380E4B3d014,
            // 0x41bE0b3368c4757B2EaD7f8Cc60D47fd64c12E9C,
            // 0xcc1f553cC4938c7F06f33BEd73323991e912D055,
            // 0x8b00335862D6d75BDE5DAB6b9911f6474f2b5B84,
            // 0xE1326241f9f30c3685F438a2F49d00A3a5412D0E,
            // 0x243648D75AFA4bd283E6E78487259E503C54d8d9,
            // 0x003728979b6d6764ca24627c7c96E498b6D1FeAD,
            // 0xDD54790958dcb11777a7fE61D9Ab5900BB94a21a,
            // 0x4E4A5E70bbdaB4B4bE333C6a072E42017B520c29
        ];

        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < assetTokens.length; i++) {
            // TODO: add to deployall scripts
            issuer.setMaxOrderDecimals(assetTokens[i], 6);
            // issuer.grantRole(issuer.ASSETTOKEN_ROLE(), assetTokens[i]);

            // DShare assetToken = DShare(assetTokens[i]);
            // assetToken.grantRole(assetToken.MINTER_ROLE(), address(issuer));
            // assetToken.grantRole(assetToken.BURNER_ROLE(), address(issuer));
        }

        vm.stopBroadcast();
    }
}
