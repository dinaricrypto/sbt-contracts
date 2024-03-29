// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/IDShare.sol";

contract Mint is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address[1] memory testWallets = [
            // add test wallets here
            address(0)
        ];

        address[1] memory mintAssets = [
            // 0x1ad40240395186ea900Cb3df6Bf5B64420CeA46D // fake USDC
            // 0x45bA256ED2F8225f1F18D76ba676C1373Ba7003F // new fake USDC
            0xcF94Bd3B94C33Db93dcAC2F8a09239D707DF6E89 // fake USDB
        ];

        for (uint256 i = 0; i < mintAssets.length; i++) {
            for (uint256 j = 0; j < testWallets.length; j++) {
                IDShare(mintAssets[i]).mint(testWallets[j], 1 ether);
            }
        }

        vm.stopBroadcast();
    }
}
