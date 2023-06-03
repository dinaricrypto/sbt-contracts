// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {SwapOrderIssuer} from "../src/issuer/SwapOrderIssuer.sol";
import {DirectBuyIssuer} from "../src/issuer/DirectBuyIssuer.sol";
import {LimitOrderIssuer} from "../src/issuer/LimitOrderIssuer.sol";
import {BridgedERC20} from "../src/BridgedERC20.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract UpgradeIssuerScript is Script {
    // WARNING: This upgrade script does not validate storage changes.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        SwapOrderIssuer swapIssuer = SwapOrderIssuer(vm.envAddress("SWAP_ISSUER"));
        DirectBuyIssuer directIssuer = DirectBuyIssuer(vm.envAddress("DIRECT_ISSUER"));
        LimitOrderIssuer limitIssuer = LimitOrderIssuer(vm.envAddress("LIMIT_ISSUER"));

        vm.startBroadcast(deployerPrivateKey);

        // deploy new implementation
        SwapOrderIssuer issuerImpl = new SwapOrderIssuer();
        // upgrade proxy to new implementation
        UUPSUpgradeable(swapIssuer).upgradeTo(address(issuerImpl));

        // deploy new implementation
        DirectBuyIssuer directIssuerImpl = new DirectBuyIssuer();
        // upgrade proxy to new implementation
        UUPSUpgradeable(directIssuer).upgradeTo(address(directIssuerImpl));

        // deploy new implementation
        LimitOrderIssuer limitIssuerImpl = new LimitOrderIssuer();
        // upgrade proxy to new implementation
        UUPSUpgradeable(limitIssuer).upgradeTo(address(limitIssuerImpl));

        vm.stopBroadcast();
    }
}
