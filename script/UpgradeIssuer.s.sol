// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {BuyOrderIssuer} from "../src/issuer/BuyOrderIssuer.sol";
import {SellOrderProcessor} from "../src/issuer/SellOrderProcessor.sol";
import {DirectBuyIssuer} from "../src/issuer/DirectBuyIssuer.sol";
import {BridgedERC20} from "../src/BridgedERC20.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract UpgradeIssuerScript is Script {
    // WARNING: This upgrade script does not validate storage changes.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("TESTNET_KEY");
        BuyOrderIssuer buyIssuer = BuyOrderIssuer(vm.envAddress("BUY_ISSUER"));
        SellOrderProcessor sellProcessor = SellOrderProcessor(vm.envAddress("SELL_PROCESSOR"));
        DirectBuyIssuer directIssuer = DirectBuyIssuer(vm.envAddress("DIRECT_ISSUER"));

        vm.startBroadcast(deployerPrivateKey);

        // deploy new implementation
        BuyOrderIssuer buyImpl = new BuyOrderIssuer();
        // upgrade proxy to new implementation
        UUPSUpgradeable(buyIssuer).upgradeTo(address(buyImpl));

        // deploy new implementation
        SellOrderProcessor sellImpl = new SellOrderProcessor();
        // upgrade proxy to new implementation
        UUPSUpgradeable(sellProcessor).upgradeTo(address(sellImpl));

        // deploy new implementation
        DirectBuyIssuer directIssuerImpl = new DirectBuyIssuer();
        // upgrade proxy to new implementation
        UUPSUpgradeable(directIssuer).upgradeTo(address(directIssuerImpl));

        vm.stopBroadcast();
    }
}
