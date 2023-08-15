// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {BuyProcessor} from "../src/orders/BuyProcessor.sol";
import {SellProcessor} from "../src/orders/SellProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {dShare} from "../src/dShare.sol";

interface IAssetToken {
    // solady roles
    function grantRoles(address user, uint256 roles) external payable;
}

contract AddTokensOldScript is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        BuyProcessor buyIssuer = BuyProcessor(vm.envAddress("BUY_ISSUER"));
        SellProcessor sellProcessor = SellProcessor(vm.envAddress("SELL_PROCESSOR"));
        BuyUnlockedProcessor directIssuer = BuyUnlockedProcessor(vm.envAddress("DIRECT_ISSUER"));

        address[1] memory paymentTokens = [
            0x45bA256ED2F8225f1F18D76ba676C1373Ba7003F // fake USDC
        ];

        address[5] memory assetTokens = [
            0x50d0A27B24423D27c8dba04213cd22f2Aa067683,
            0x3A775507F2f90BBFf1d313cC149bcbB48f0C7315,
            0x0a98264bE733302AC44aFEE7906cEc1F42CF6E3c,
            0x914A2410127cbe1f08b873358225B1A053b7b5d5,
            0x9A940A40650c0d4B8128316739cDE69EA54aEF08
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
