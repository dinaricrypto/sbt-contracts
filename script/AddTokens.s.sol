// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
// import {DShareFactory} from "../src/DShareFactory.sol";
import {DShare} from "../src/DShare.sol";

contract AddTokensScript is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        OrderProcessor issuer = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));

        address[42] memory assetTokens = [
            // ----- sandbox
            0xD771a71E5bb303da787b4ba2ce559e39dc6eD85c,
            0x92d95BCB50B83d488bBFA18776ADC1553d3a8914,
            0x3472DEd4C1C6d896D5c8B884164331fd3a3D0a48,
            0x56C4C5986C29d2289933B1D0baD13C01295c9Cd7,
            0xC470cfBc19Ec46180ceb7D165A064B186d5fDF14,
            0x0a19778934EEb0091895fA0Ccf276608DB38235f,
            0xa87c499eA414A944041165A204f9aAea1b32297d,
            0x4B47153A241b9d22ae37c2aAEe7A6519fF2Dbfc6,
            0x7e484f9eb31219e8977348C07407e17afF8991E7,
            0xF9de5DfAEB1268713B8729731e667992FBfFB6F8,
            0x7ec6109693fe6544DE4151c51FB4A41b279AdcE6,
            0xa09aFBD99c4E83Bc14BdEa3c72345D23E8dFB9Ac,
            0xA061A48c3B7E4A470BfA4FbC71508D32DE9588DF,
            0x27F83Fd17AF5ED08F3BA9Fd62dD1F0b3cFb07344,
            0xC52375178081735252bAcaB02635C971296Fc83b,
            0x18aD1A35134F813fBEB4526d655D9d39783512D2,
            0x7B58f454c36Edc0FBDEDfA8E0D4392A1a4c0b96c,
            0x9ee4a6De7487Ea8feACca65a98f881c5eA6784f8,
            0x9bEF741B1214A4428b101A4C3c63Eb46Ce1F38E8,
            0x43Dc9C7a41Ef617FF5aBc2ed84FC402F24700698,
            0xC12CC2f1d673314dDd305056da018D8157118a29,
            0x8c7074B3e3DF4C51c52c164b574aD782468eB168,
            0xdc2C5910d367f62F2F3234C9eaa5Afb12948Ef01,
            0xB9162e5055bedEC86C07BdB5a40883BEa5e46d64,
            0x990cC21907f98AA370DcAd909f40949487BEFc0a,
            0x431F50Af2f454AbAec8887CE127215AF9CEB1848,
            0xC9A1EFd352a39BeFea07dAc865F5001faEcDeaE0,
            0x73423B6D6493471C9fde797CC9c1C316Bffc6150,
            0x33e8a0475f6C64823Dc15a6efeE4E434Ddcc3Fb7,
            0x56793CCa0F243E34FDE3997CdbbeD278c500E66e,
            0x6aB28DF2A8B70f6E249B5CC4fa584a6a7686A014,
            0x220d88F3b091Fa54F6A0946Fc896C847fe49C3Dc,
            0xCA450e77A0c2550e59C1F80Cb178583a3d7f7b76,
            0xC9560C59A79977f9d40AC237C9017FdA3E390036,
            0x9e3e428322Af73964481821c699D0E7eEdb0Fb50,
            0xBbd8b9Ae374617a48FF28f532B4AEA4385Ae57F7,
            0x339A98c1F169319e647ca2e1673f104A03C82bE8,
            0xc9C1445a49EA667BFb9d110906718BF15C9D4A4f,
            0xb0B0833bb5d083287Bc757C60Ebda076EA32E45c,
            0xa44c4115d7DeF2da38fBc91B0f3A923440610C52,
            0x3bC0270d9685b109d77CcC719900AfADB6C236F5,
            0xB0513bEa108c30A3D890DE05385DC7BFE62C113d
            // -----
            // 0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7,
            // 0x3AD63B3C0eA6d7A093ff98fdE040baddc389EcDc,
            // 0xF4BD09B048248876E39Fcf2e0CDF1aee1240a9D2,
            // 0x9C46e1B70d447B770Dbfc8D450543a431aF6DF3A,
            // 0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c,
            // 0x5B6424769823e82A1829B0A8bcAf501bFFD90d25,
            // 0x77308F8B63A99b24b262D930E0218ED2f49F8475,
            // 0x8E50D11a54CFF859b202b7Fe5225353bE0646410,
            // 0x8240aFFe697CdE618AD05c3c8963f5Bfe152650b,
            // 0x3c9f23dB4DDC5655f7be636358D319A3De1Ff0c4,
            // 0x519062155B0591627C8A0C0958110A8C5639DcA6,
            // 0xF1f18F765F118c3598cC54dCaC1D0e12066263Fe,
            // 0x36d37B6cbCA364Cf1D843efF8C2f6824491bcF81,
            // 0x46b979440AC257151EE5a5bC9597B76386907FA1,
            // 0x67BaD479F77488f0f427584e267e66086a7Da43A,
            // 0xd8F728AdB72a46Ae2c92234AE8870D04907786C5,
            // 0x118346C2bb9d24412ed58C53bF9BB6f61A20d7Ec,
            // 0x0c29891dC5060618c779E2A45fbE4808Aa5aE6aD,
            // 0xeb0D1360A14c3b162f2974DAA5d218E0c1090146
            // ----
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
            if (issuer.maxOrderDecimals(assetTokens[i]) != 6) {
                issuer.setMaxOrderDecimals(assetTokens[i], 6);
            }
            if (!issuer.hasRole(issuer.ASSETTOKEN_ROLE(), assetTokens[i])) {
                issuer.grantRole(issuer.ASSETTOKEN_ROLE(), assetTokens[i]);
            }

            DShare assetToken = DShare(assetTokens[i]);
            if (!assetToken.hasRole(assetToken.MINTER_ROLE(), address(issuer))) {
                assetToken.grantRole(assetToken.MINTER_ROLE(), address(issuer));
            }
            if (!assetToken.hasRole(assetToken.BURNER_ROLE(), address(issuer))) {
                assetToken.grantRole(assetToken.BURNER_ROLE(), address(issuer));
            }
        }

        vm.stopBroadcast();
    }
}
