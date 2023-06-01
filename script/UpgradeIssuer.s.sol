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

        SwapOrderIssuer issuerImpl = new SwapOrderIssuer();
        UUPSUpgradeable(swapIssuer).upgradeTo(address(issuerImpl));

        DirectBuyIssuer directIssuerImpl = new DirectBuyIssuer();
        UUPSUpgradeable(directIssuer).upgradeTo(address(directIssuerImpl));

        LimitOrderIssuer limitIssuerImpl = new LimitOrderIssuer();
        UUPSUpgradeable(limitIssuer).upgradeTo(address(limitIssuerImpl));

        vm.stopBroadcast();
    }
}
