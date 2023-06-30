// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/IMintBurn.sol";

contract MintScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("TESTNET_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address[1] memory testWallets = [
            // add test wallets here
            address(0)
        ];

        address[1] memory mintAssets = [
            0x1ad40240395186ea900Cb3df6Bf5B64420CeA46D // fake USDC
        ];

        for (uint256 i = 0; i < mintAssets.length; i++) {
            for (uint256 j = 0; j < testWallets.length; j++) {
                IMintBurn(mintAssets[i]).mint(testWallets[j], 10_000 ether);
            }
        }

        vm.stopBroadcast();
    }
}
