// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/IMintBurn.sol";

contract MintScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address[6] memory testWallets = [
            0xcF86069157B0992d6d62E02C0D1384df1A7769a1,
            0x764c37250DDD0D8f1f26b91d9c4FaE83c21fAE94,
            0xF8797fE9A333b7744cB5D6A892Fc29E9bb54F22B,
            0x6772b9524D92001C8b3c1c2F736e3c396dD7f234,
            0xacA8D039E0006153fA688fa470DC64285247a7Ae,
            0x4181803232280371E02a875F51515BE57B215231
        ];

        address[6] memory mintAssets = [
            0x90d3AF79BaDC62952E0bdA7F06468f1E3c3658F9, // fake USDC
            0x50d0A27B24423D27c8dba04213cd22f2Aa067683,
            0x3A775507F2f90BBFf1d313cC149bcbB48f0C7315,
            0x0a98264bE733302AC44aFEE7906cEc1F42CF6E3c,
            0x914A2410127cbe1f08b873358225B1A053b7b5d5,
            0x9A940A40650c0d4B8128316739cDE69EA54aEF08
        ];

        for (uint256 i = 0; i < mintAssets.length; i++) {
            for (uint256 j = 0; j < testWallets.length; j++) {
                IMintBurn(mintAssets[i]).mint(testWallets[j], 100000 ether);
            }
        }

        vm.stopBroadcast();
    }
}
