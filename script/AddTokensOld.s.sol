// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {BuyOrderIssuer} from "../src/issuer/BuyOrderIssuer.sol";
import {SellOrderProcessor} from "../src/issuer/SellOrderProcessor.sol";
import {DirectBuyIssuer} from "../src/issuer/DirectBuyIssuer.sol";
import {BridgedERC20} from "../src/BridgedERC20.sol";

interface IAssetToken {
    // solady roles
    function grantRoles(address user, uint256 roles) external payable;
}

contract AddTokensOldScript is Script {
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
            0x47FAB66a84aCE0A1DB2234257d98C7CcE7Fd0634,
            0xa4218E64F4A1bD5E7eBf1226e4351F969d8f8139,
            0x98bcaebBfd4b26d90b93E71840c519e088fEDC01,
            0xb93998bB94d524ee138b8984f9869E5cdA72083E,
            0xbD1C52c2C622541C01D23412550e0D8B0eCF3882
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

            IAssetToken assetToken = IAssetToken(assetTokens[i]);
            uint256 role = 1 << 1;
            assetToken.grantRoles(address(buyIssuer), role);
            assetToken.grantRoles(address(sellProcessor), role);
            assetToken.grantRoles(address(directIssuer), role);
        }

        vm.stopBroadcast();
    }
}
