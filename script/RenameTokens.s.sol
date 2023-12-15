// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {WrappedDShare} from "../src/WrappedDShare.sol";
import {LibString} from "solady/src/utils/LibString.sol";

contract RenameTokens is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");

        // arbitrum
        address[18] memory assetTokens = [
            0xA6B1bC15a4289899309BA0439D4037084fa2d457,
            0xee0d00A79aFeB121880f5Bf2273DEbbF7f60EA02,
            0x5b4C01175e9809A7f352197E953F8D9A2aE2d12F,
            0xF82F6801FA5Ab466C8820F08C9C7Adf893AC8d6F,
            0xbAc491F9cdD0c1A05c18492232827ca009B64945,
            0xbdA5a1e73410730325CEA424F3DbD8A2eCc69514,
            0x9Ea41FDFb479A0Eb2b43EF4cB2248E13436f5e07,
            0xF8C652054a60224E2d9c774Bfd118f6a27d5bCEf,
            0x3c5bEbe8998137E390b0cb791B42bF538353451b,
            0xb5d09652f40630b287bC067270C79E1402f28599,
            0xD767EE961A00921D69721c0F9999546d5235e6f9,
            0xADf3Cd8759Bd8bA9106342d1494b4Fb4b3720923,
            0x42112C40C4d4f5be3b64B113A55D307a30716964,
            0x407274ABb9241Da0A1889c1b8Ec65359dd9d316d,
            0xef8c9C08EE50bD31377a309b879FC9AFD1302c83,
            0xCc3Dc0Ac609E6b78bb8CD7a3b27C2C7688272F8a,
            0x6bb71b2bdd892c5EfB960a76EDeC03b1F04551F4,
            0x0C39B0146F774FE4aEBC62E1dDDE7AA03A3534f1
        ];

        // sepolia - stage
        // address[1] memory assetTokens = [
        //     0xc799Ff17777Ff4eB796868076084171D475Ba993
        // ];

        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < assetTokens.length; i++) {
            WrappedDShare assetToken = WrappedDShare(assetTokens[i]);
            string memory symbol = assetToken.symbol();
            string memory newSymbol = string.concat(LibString.slice(symbol, 1), "w");

            assetToken.setSymbol(newSymbol);
            console.log("Renamed token %s -> %s", symbol, newSymbol);
        }

        vm.stopBroadcast();
    }
}
