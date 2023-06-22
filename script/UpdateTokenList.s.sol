// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {BridgedERC20} from "../src/BridgedERC20.sol";

contract UpdateTokenListScript is Script {
    uint256 constant n = 13;

    function run() external {
        // load config
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        // uint256 ownerKey = vm.envUint("OWNER_KEY");
        // address owner = vm.addr(ownerKey);

        console.log("deployer: %s", deployer);
        // console.log("owner: %s", owner);

        address[n] memory addresses = [
            0x2888c0aC959484e53bBC6CdaBf2b8b39486225C6,
            0x6AE848Cd367aC2559abC06BdbD33bEed6B2f49d5,
            0x20f11c1aBca831E235B15A4714b544Bb968f8CDF,
            0xa40c0975607BDbF7B868755E352570454b5B2e48,
            0xFdC642c9B59189710D0cac0528D2791968cf560a,
            0x2414faE77CF726cC2287B81cf174d9828adc6636,
            0x9bd7A08cD17d10E02F596Aa760dfE397C57668b4,
            0x5a8A18673aDAA0Cd1101Eb4738C05cc6967b860f,
            0x9F1f1B79163dABeDe8227429588289218A832359,
            0x70732186F811f205c28C583096C8ae861B359CEf,
            0xf67e6E9a4B62accd0Aa9DD113a7ef8a0653Bb9Cb,
            0x58A8eeC9b82CdF13090A2032235Beb9152e7eB3b,
            0x1ba13cD81B018e06d7a7EaD033D5131115fE6C82
        ];

        string[n] memory names = [
            "Tesla, Inc.",
            "NVIDIA Corporation",
            "Microsoft Corporation",
            "Meta Platforms, Inc.",
            "Netflix, Inc.",
            "Apple Inc.",
            "Alphabet Inc. (Class A)",
            "Amazon.com, Inc.",
            "PayPal Holdings, Inc.",
            "Pfizer, Inc.",
            "Walt Disney Company",
            "SPDR S&P 500 ETF Trust",
            "WisdomTree Floating Rate Treasury Fund"
        ];

        string[n] memory symbols =
            ["TSLA", "NVDA", "MSFT", "META", "NFLX", "AAPL", "GOOGL", "AMZN", "PYPL", "PFE", "DIS", "SPY", "USFR"];
        for (uint256 i = 0; i < n; i++) {
            names[i] = string.concat(names[i], " - Dinari");
            symbols[i] = string.concat(symbols[i], ".d");
        }

        // start
        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < n; i++) {
            // deploy token
            BridgedERC20 token = BridgedERC20(addresses[i]);

            // update metadata
            token.setName(names[i]);
            token.setSymbol(symbols[i]);
        }

        vm.stopBroadcast();
    }
}
