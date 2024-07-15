// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {DShare} from "../src/DShare.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract AddTokensScript is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        OrderProcessor issuer = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));

        address[38] memory assetTokens = [
            // arbitrum
            // 0x46b979440AC257151EE5a5bC9597B76386907FA1,
            // 0x67BaD479F77488f0f427584e267e66086a7Da43A,
            // 0xd8F728AdB72a46Ae2c92234AE8870D04907786C5,
            // 0x0A2919147b871a0Fc90f04944e31FAd56d9AF666,
            // 0xc20770116f2821d550574C2B9CE1b4bAA7012377,
            // 0x97Ec5DAdA8262BD922BfFd54a93F5A11EfE0B136,
            // 0x8240aFFe697CdE618AD05c3c8963f5Bfe152650b,
            // 0x3c9f23dB4DDC5655f7be636358D319A3De1Ff0c4,
            // 0x9dA913f4DCa9B210a232d588113047685a4ed4B1,
            // 0xc52915Fe75dc8db9fb6306f43AAef1344E0837AB,
            // 0xDD92f0723a7318e684A88532CAC2421E3cC9968e,
            // 0x2B7c643b42409F352B936BF07e0538ba20979Bff,
            // 0x0c59F6b96d3CaC58240429c7659eC107f8b1efA7,
            // 0x14297BE295ab922458277BE046e89f73382bDF8e,
            // 0xd883bcF80b2b085FA40CC3e2416b4AB1CBCA649E,
            // 0x118346C2bb9d24412ed58C53bF9BB6f61A20d7Ec,
            // 0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7,
            // 0x13F950EE286A5be0254065D4B66420fC0E57adfC,
            // 0xc1Ba16AFDcb3A41242944C9FaaCCD9fb6f2B428C,
            // 0x9C46e1B70d447B770Dbfc8D450543a431aF6DF3A,
            // 0xeb0D1360A14c3b162f2974DAA5d218E0c1090146,
            // 0x0c29891dC5060618c779E2A45fbE4808Aa5aE6aD,
            // 0xAD6a646C1B262586eF3A8B6C6304E7C9218EcAC4,
            // 0x0B5ac0d7DCf6964609a12aF4f6c6f3C257070193,
            // 0x8E50D11a54CFF859b202b7Fe5225353bE0646410,
            // 0x519062155B0591627C8A0C0958110A8C5639DcA6,
            // 0x77308F8B63A99b24b262D930E0218ED2f49F8475,
            // 0x3AD63B3C0eA6d7A093ff98fdE040baddc389EcDc,
            // 0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c,
            // 0xF1f18F765F118c3598cC54dCaC1D0e12066263Fe,
            // 0x5B6424769823e82A1829B0A8bcAf501bFFD90d25,
            // 0x36d37B6cbCA364Cf1D843efF8C2f6824491bcF81,
            // 0x1820872e193D48F59ec1B9383Da6404b58e7B803,
            // 0xB1284F6b3E487E3F773e9Ad40F337C3B3cdA5c69,
            // 0x026FdF3024953cb2e8982bc11c67d336F37A5044,
            // 0x3619ca1e96c629f7D71C1b03dc0Ee56479356228,
            // 0x2824eFE5CeDB3BC8730E412981997daC7C7640C2,
            // 0xa6F344aBc6e2501b2B303fCbbA99CD89F136b5FB,
            // 0x769fF50fD49900a6c53b2aF049eACB83dAD52Bdf,
            // 0xF4BD09B048248876E39Fcf2e0CDF1aee1240a9D2
            // ethereum
            0x251530c7f24d6904A31425b9AFa24b0e1E5AAfdE,
            0xAC20315350d7B59cBE846144f5Eb8a6D1DF1F5fC,
            0x0ECB3513eBf1E62be765452900608Aa957dBD13D,
            0xAf614642E58C65B71a3aaAB2d3Afc20e5cb93246,
            0xD2a64Bb1776F02E6B2b5503fE6a8CA6bF1f46D07,
            0x9E6dbDE4211e6853B33B8bCd5Ce82144997C63BA,
            0x0C7Ec64a7b3416bc3578E02d4b1e5763Da756183,
            0x81B11D330D9Af45599bE0580b9Bcba7F4E57BD35,
            0x12dd3F826Cf73e30203476B2988bCaefcC3AC68c,
            0x961cA9D6E644b5509654f3D5a250bB03f2e702b6,
            0xA2D43E3398ECF6A7A32Ff50A49e0096ea122Ec4b,
            0xd0f48CAf8fDb1E7b1FB8B08B914E0b44Ed0aAdE0,
            0x0aF5b873DF94efeBA34c0B0A9FA34a8C13E078cd,
            0xc4a217A8b2Cdf85eB8206391ae3723d72B3A4E04,
            0xA64C9F707bBb4cBC4E22F596A53D85b3ab7000F8,
            0x68E670D2f9B792f034a1826cF4A8F180C9952Cb6,
            0xEaC2887725a9782440606Eb655Bc14047ee57cd6,
            0x0bbeB8decEEccb8Ba651bC08e0482b006b8A4459,
            0x69bb721889FA2714aB0fd769e9c5D5BA3ecA0494,
            0x62Ec03C917FaCE0E6841AFdAfC166bF571E55E4F,
            0x0B955628aCf18834A7BF81FbE303c36221f2fD26,
            0xaEB0A5d56de94479cdA178977570FD9079500527,
            0xcd7C6Ed75151745C893DFC1Dca1dAa1D55034E67,
            0xAEDC5e1E05c2fB8840F6D6dF4E8F63e983C32BD5,
            0x18c278Edc2ED4ed9D23A8A73A3a6eD014094B784,
            0x149Ae2607D2d3C79bf053D720CacCF831d48D55F,
            0xC4C29b8cf6Fc1CD975d7Df3442B4487FE73ba928,
            0x32E739C725Ff09Ca5b97cE69f28Bc3AEC120c736,
            0xC45fB996F73f23F61d08b5B3618Ef3CaB53D6DCA,
            0x5CB380fa420c33aC896A7B1dc580188C24582917,
            0xEc3E2998C87ac9bcED45381F84932c877cAD6930,
            0xEa142f62ed971651691c6E22c6b78eC488c61F9D,
            0xd71B200bF061509B85dF50Cc0D8CDee8818A4577,
            0x33E5b290bAdbD8Ba868b51a72ab6062601F9E9B2,
            0x2CAD08360009226261ab4d32684aacDbBeC3F8dA,
            0x3c4024408eFaC2DBF7ED453C95D9D97889E4846A,
            0xc4C6213024D9aDC5132707942905918DF7FBBBE8,
            0xF12a38e6e51913eA04D70dBa97D7420a13Fd7941
            // blast
            // 0xB66fb7A6baAeCe3edD6b4D506b0e2f0BAE5Fc6E0,
            // 0x6C627B1E04edE1A6E0619727C70F69cB259d06f8,
            // 0x53ca87B939cFdBc90b6F28751E164E77165ae7d4,
            // 0x42e4981De9bC8FD4726775f62066CAbbE78DEAB8,
            // 0x93A9F06576CFE91e8C408467CD684Df42CA23c23,
            // 0x30FA6b130399CBa3037f77472bb4a681c6c3153d,
            // 0xC5dB3ef748dD0f3D4cC883055f1B9B55Fa5C89C6,
            // 0xa13b4574e7b198FA156Eae7B65673CE94e6770b6,
            // 0xEefBaea4A50154c56eC0072ec32dBF471CDA5Fa6,
            // 0x9280161fa9c60B95da37Ae35f52A6Cea979E0F2F,
            // 0x51d9183ec33C91EaE7186A10D7b66C4A57663A6C,
            // 0xFcBe84B53fD3eD33b5Dfa82fB005603daa5204A7,
            // 0x74798fd1a87E07c7b8bf89FaFc922E4BF10c35a9,
            // 0x01E8bD212f5F319E7126b62aA020831b92e19cD9,
            // 0x665b080aFfB4a7e0ceae3ce88Ba0401C864635d8,
            // 0x323D74e1Dd1C9551d37d56BE5312E73E31d9D3ea,
            // 0x401120ACdA5cE0dce78f0a0A449dB3B3477aA688,
            // 0xAA1dbb5DD00595c8F50Ff53dfa9C65Eb0624d858,
            // 0x80B2ae2cFD411C98aA74C75A40B930a337612D29,
            // 0xcd14b65d43489F8168dE5Bf6A6c74f631bcCEb05,
            // 0x4f6b23Af253Cd046f319DA437cD48618D447A18a,
            // 0x89D0A55a8c2d94c0d4a91C6e3de58DD131Ad87Fc,
            // 0xd951722f5309479cDe8ed719fE3e13596290A324,
            // 0xDbC13Aa0203e8320fAF6a9b5651e9241032376be,
            // 0xbf26ECE8626C30f6eFc6518aC93a773D24E6ff83,
            // 0x28215D9e6444116E194405E93CcF68afDE544D5C,
            // 0xbf286A9c026F02DD4D2e3fc3887e77e425D15A11,
            // 0xBe2019C75EbF9eAD0AB3513fd3c1733F2eB490E7,
            // 0xc85b6cFab89317B952dab87a8f85B8Eb130ad411,
            // 0xc47c717F410c9Be5Dee728129e62C2Da3354E96E,
            // 0xD2948c7824e1B872dAF8c304052242D2aDe4d027,
            // 0x35C6d29217f2AE3a73c72a1eF4A2784a8f55a686,
            // 0xA5de16db7c14Cd87fb35042Ed8E7A6f4f00b7f26,
            // 0x9558e1217E0cB47Ade9B5F63Cc5ACA8D47691Ab7,
            // 0xA9053e91A9EA714023de577929C3E119264D80D6,
            // 0x296c2186948712D66bEf4778567c4d2f734BFF3c,
            // 0x64931990e69B55ff7aCaF0f20416D29B20855bE6,
            // 0xf0a23FD4a51e9c5055b912E41A6052b56E6108b8
        ];

        vm.startBroadcast(deployerPrivateKey);

        bytes[] memory issuerCalls = new bytes[](assetTokens.length);

        for (uint256 i = 0; i < assetTokens.length; i++) {
            // TODO: add to deployall scripts
            issuerCalls[i] = abi.encodeWithSelector(
                issuer.setOrderDecimalReduction.selector, assetTokens[i], IERC20Metadata(assetTokens[i]).decimals() - 9
            );
            // issuer.setMaxOrderDecimals(assetTokens[i], 9);
            // issuer.grantRole(issuer.ASSETTOKEN_ROLE(), assetTokens[i]);
            // directIssuer.setMaxOrderDecimals(assetTokens[i], 9);
            // directIssuer.grantRole(directIssuer.ASSETTOKEN_ROLE(), assetTokens[i]);

            // DShare assetToken = DShare(assetTokens[i]);
            // assetToken.grantRole(assetToken.MINTER_ROLE(), address(issuer));
            // assetToken.grantRole(assetToken.BURNER_ROLE(), address(issuer));
        }

        issuer.multicall(issuerCalls);

        vm.stopBroadcast();
    }
}
