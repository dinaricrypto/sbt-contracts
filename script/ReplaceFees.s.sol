// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {FlatOrderFees, IOrderFees} from "../src/FlatOrderFees.sol";
import {SwapOrderIssuer} from "../src/SwapOrderIssuer.sol";
import {DirectBuyIssuer} from "../src/DirectBuyIssuer.sol";
import {LimitOrderIssuer} from "../src/LimitOrderIssuer.sol";
import {BridgedERC20} from "../src/BridgedERC20.sol";

contract ReplaceFeesScript is Script {
    // This script will deploy a new IORderFees and replace existing fee contract for issuers.
    // To change the fee parameters on an active fee contract, call methods on the contract directly.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        SwapOrderIssuer swapIssuer = SwapOrderIssuer(vm.envAddress("SWAP_ISSUER"));
        DirectBuyIssuer directIssuer = DirectBuyIssuer(vm.envAddress("DIRECT_ISSUER"));
        LimitOrderIssuer limitIssuer = LimitOrderIssuer(vm.envAddress("LIMIT_ISSUER"));

        vm.startBroadcast(deployerPrivateKey);

        IOrderFees orderFees = new FlatOrderFees(deployer, 0.005 ether);

        swapIssuer.setOrderFees(orderFees);
        directIssuer.setOrderFees(orderFees);
        limitIssuer.setOrderFees(orderFees);

        vm.stopBroadcast();
    }
}
