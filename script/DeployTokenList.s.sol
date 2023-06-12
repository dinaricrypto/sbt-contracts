// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {BridgedERC20} from "../src/BridgedERC20.sol";
import {ITransferRestrictor} from "../src/ITransferRestrictor.sol";
import {BuyOrderIssuer} from "../src/issuer/BuyOrderIssuer.sol";
import {SellOrderProcessor} from "../src/issuer/SellOrderProcessor.sol";
import {DirectBuyIssuer} from "../src/issuer/DirectBuyIssuer.sol";

contract DeployTokenListScript is Script {
    function run() external {
        // load config
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        ITransferRestrictor restrictor = ITransferRestrictor(vm.envAddress("TRANSFER_RESTRICTOR"));
        BuyOrderIssuer buyIssuer = BuyOrderIssuer(vm.envAddress("BUY_ISSUER"));
        SellOrderProcessor sellProcessor = SellOrderProcessor(vm.envAddress("SELL_PROCESSOR"));
        DirectBuyIssuer directIssuer = DirectBuyIssuer(vm.envAddress("DIRECT_ISSUER"));

        // start
        vm.startBroadcast(deployerPrivateKey);

        string[13] memory names = [
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
        for (uint256 i = 0; i < names.length; i++) {}

        string[13] memory symbols =
            ["TSLA", "NVDA", "MSFT", "META", "NFLX", "AAPL", "GOOGL", "AMZN", "PYPL", "PFE", "DIS", "SPY", "USFR"];
        for (uint256 i = 0; i < names.length; i++) {
            names[i] = string.concat(names[i], " - Dinari");
            symbols[i] = string.concat(symbols[i], ".D");
        }

        for (uint256 i = 0; i < 5; i++) {
            // deploy token
            BridgedERC20 token = new BridgedERC20(deployerAddress, names[i], symbols[i], "", restrictor);

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
