// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {DShare} from "../src/DShare.sol";
import {WrappedDShare} from "../src/WrappedDShare.sol";

contract RenameTokens is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");

        // 0xeC0CC8140e0587029477e762d1f3616F3fD9cdB7	7887
        // 0xd883bcF80b2b085FA40CC3e2416b4AB1CBCA649E	42161
        // 0xd7d2A97cB861ff2a3B6E64f0d6bc51246b8529fC	98865
        // 0x9E6dbDE4211e6853B33B8bCd5Ce82144997C63BA	1
        // 0x89D0A55a8c2d94c0d4a91C6e3de58DD131Ad87Fc	81457
        // 0xD5EAB2d9E01442BfcA720F6f15451555dD003f40	8453
        // 0x8c7074B3e3DF4C51c52c164b574aD782468eB168	11155111

        // Wrapped
        // 0xB4C1fD031209615be2C909887480A856c89dc0dC    1
        // 0xb5fCAeEF1deF20fcD1C2650da3B20C20cE111038    7887
        // 0x9032e4deB459Fe147B6de4Afdba5675D509a8B1C    8453
        // 0x4C4C794adeC19665f2Ac4d3D7abA7e761d24920A    42161
        // 0x817CD5a9832B74BEEe10DA349e116f0Cf18CFa2b    81457
        // 0x8a7af667e40849a8D3585FAA5E76b5A6D9E01997   98865
        // 0xAfa9B3e27Bf868E6783d4699BF97d8D4B376C200   11155111

        DShare dshare = DShare(0xeC0CC8140e0587029477e762d1f3616F3fD9cdB7);
        WrappedDShare wdshare = WrappedDShare(0xb5fCAeEF1deF20fcD1C2650da3B20C20cE111038);

        vm.startBroadcast(deployerPrivateKey);

        string memory symbol = dshare.symbol();
        assert(keccak256(abi.encode(symbol)) == keccak256(abi.encode("SQ.d")));
        string memory newSymbol = "XYZ.d";
        dshare.setSymbol(newSymbol);
        console.log("Renamed token %s -> %s", symbol, newSymbol);

        symbol = wdshare.symbol();
        assert(keccak256(abi.encode(symbol)) == keccak256(abi.encode("SQ.dw")));
        newSymbol = "XYZ.dw";
        wdshare.setSymbol(newSymbol);
        console.log("Renamed token %s -> %s", symbol, newSymbol);

        vm.stopBroadcast();
    }
}
