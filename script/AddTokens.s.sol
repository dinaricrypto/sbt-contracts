// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {SwapOrderIssuer} from "../src/SwapOrderIssuer.sol";
import {DirectBuyIssuer} from "../src/DirectBuyIssuer.sol";
import {LimitOrderIssuer} from "../src/LimitOrderIssuer.sol";
import {BridgedERC20} from "../src/BridgedERC20.sol";

contract AddTokensScript is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        SwapOrderIssuer swapIssuer = SwapOrderIssuer(vm.envAddress("SWAP_ISSUER"));
        DirectBuyIssuer directIssuer = DirectBuyIssuer(vm.envAddress("DIRECT_ISSUER"));
        LimitOrderIssuer limitIssuer = LimitOrderIssuer(vm.envAddress("LIMIT_ISSUER"));

        address[1] memory paymentTokens = [
            0x1ad40240395186ea900Cb3df6Bf5B64420CeA46D // fake USDC
        ];

        address[5] memory assetTokens = [
            0x50d0A27B24423D27c8dba04213cd22f2Aa067683,
            0x3A775507F2f90BBFf1d313cC149bcbB48f0C7315,
            0x0a98264bE733302AC44aFEE7906cEc1F42CF6E3c,
            0x914A2410127cbe1f08b873358225B1A053b7b5d5,
            0x9A940A40650c0d4B8128316739cDE69EA54aEF08
        ];

        vm.startBroadcast(deployerPrivateKey);

        // assumes all issuers have the same role
        uint256 paymentTokenRole = swapIssuer.PAYMENTTOKEN_ROLE();
        for (uint256 i = 0; i < paymentTokens.length; i++) {
            swapIssuer.grantRoles(paymentTokens[i], paymentTokenRole);
            directIssuer.grantRoles(paymentTokens[i], paymentTokenRole);
            limitIssuer.grantRoles(paymentTokens[i], paymentTokenRole);
        }

        // assumes all issuers have the same role
        uint256 assetTokenRole = swapIssuer.ASSETTOKEN_ROLE(); 
        uint256 minterRole = BridgedERC20(assetTokens[0]).minterRole();
        for (uint256 i = 0; i < assetTokens.length; i++) {
            swapIssuer.grantRoles(assetTokens[i], assetTokenRole);
            directIssuer.grantRoles(assetTokens[i], assetTokenRole);
            limitIssuer.grantRoles(assetTokens[i], assetTokenRole);
            BridgedERC20(assetTokens[i]).grantRoles(address(swapIssuer), minterRole);
            BridgedERC20(assetTokens[i]).grantRoles(address(directIssuer), minterRole);
            BridgedERC20(assetTokens[i]).grantRoles(address(limitIssuer), minterRole);
        }

        vm.stopBroadcast();
    }
}
