// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {dShare} from "../src/dShare.sol";
import {ITransferRestrictor} from "../src/ITransferRestrictor.sol";
import {MarketBuyProcessor} from "../src/issuer/MarketBuyProcessor.sol";
import {MarketSellProcessor} from "../src/issuer/MarketSellProcessor.sol";
import {DirectBuyIssuer} from "../src/issuer/DirectBuyIssuer.sol";

contract DeployTokenListScript is Script {
    uint256 constant n = 13;

    function run() external {
        // load config
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        // uint256 ownerKey = vm.envUint("OWNER_KEY");
        // address owner = vm.addr(ownerKey);

        ITransferRestrictor restrictor = ITransferRestrictor(vm.envAddress("TRANSFER_RESTRICTOR"));
        MarketBuyProcessor buyIssuer = MarketBuyProcessor(vm.envAddress("BUY_ISSUER"));
        MarketSellProcessor sellProcessor = MarketSellProcessor(vm.envAddress("SELL_PROCESSOR"));
        DirectBuyIssuer directIssuer = DirectBuyIssuer(vm.envAddress("DIRECT_ISSUER"));

        console.log("deployer: %s", deployer);
        // console.log("owner: %s", owner);

        // start
        vm.startBroadcast(deployerPrivateKey);

        string[n] memory names = [
            "Tesla, Inc.",
            "Nvidia",
            "Microsoft",
            "Meta Platforms",
            "Netflix",
            "Apple Inc.",
            "Alphabet Inc. (Class A)",
            "Amazon",
            "PayPal",
            "Pfizer",
            "Disney",
            "SPDR S&P 500 ETF Trust",
            "WisdomTree Floating Rate Treasury Fund"
        ];

        string[n] memory symbols =
            ["TSLA", "NVDA", "MSFT", "META", "NFLX", "AAPL", "GOOGL", "AMZN", "PYPL", "PFE", "DIS", "SPY", "USFR"];
        for (uint256 i = 0; i < n; i++) {
            names[i] = string.concat(names[i], " - Dinari");
            symbols[i] = string.concat(symbols[i], ".D");
        }

        for (uint256 i = 0; i < n; i++) {
            // deploy token
            dShare token = new dShare(deployer, names[i], symbols[i], "", restrictor);

            // allow issuers to mint and burn
            token.grantRole(token.MINTER_ROLE(), address(buyIssuer));
            token.grantRole(token.BURNER_ROLE(), address(sellProcessor));
            token.grantRole(token.MINTER_ROLE(), address(directIssuer));

            // allow orders for token on issuers
            buyIssuer.grantRole(buyIssuer.ASSETTOKEN_ROLE(), address(token));
            sellProcessor.grantRole(sellProcessor.ASSETTOKEN_ROLE(), address(token));
            directIssuer.grantRole(directIssuer.ASSETTOKEN_ROLE(), address(token));
        }

        vm.stopBroadcast();
    }
}
