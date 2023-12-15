// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {WrappedDShare} from "../src/WrappedDShare.sol";

contract RenameTokens is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");

        address[5] memory assetTokens = [
            0xBCf1c387ced4655DdFB19Ea9599B19d4077f202D,
            0x1128E84D3Feae1FAb65c36508bCA6E1FA55a7172,
            0xd75870ab648E5158E07Fe0A3141AbcBd4Ac329aa,
            0x54c0f59d9a8CF63423A7137e6bcD8e9bA169216e,
            0x0c55e03b976a57B13Bf7Faa592e5df367c57f1F1
        ];

        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < assetTokens.length; i++) {
            WrappedDShare assetToken = WrappedDShare(assetTokens[i]);
            assetToken.setSymbol("wDSHARE");
        }

        vm.stopBroadcast();
    }
}
