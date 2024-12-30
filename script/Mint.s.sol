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
            0x4181803232280371E02a875F51515BE57B215231
        ];

        address[1] memory mintAssets = [
            0xa56f050AF537D1BAe27DD7b1Bcc6cd01DcC94Acb
        ];

        for (uint256 i = 0; i < mintAssets.length; i++) {
            for (uint256 j = 0; j < testWallets.length; j++) {
                IDShare(mintAssets[i]).mint(testWallets[j], 1 ether);
            }
        }

        vm.stopBroadcast();
    }
}
