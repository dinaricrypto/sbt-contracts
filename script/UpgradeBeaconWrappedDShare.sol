// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {WrappedDShare} from "../src/WrappedDShare.sol";
import {console2} from "forge-std/console2.sol";

interface IMulticall3 {
    struct Call3 {
        address target;
        bool allowFailure;
        bytes callData;
    }

    function aggregate3(Call3[] calldata calls) external payable returns (bool[] memory success, bytes[] memory results);
}

contract UpgradeWrappedDShareScript is Script {
    UpgradeableBeacon beacon = UpgradeableBeacon(0xad20601C7a3212c7BbF2ACdFEDBAD99d803bC7F5);
    IMulticall3 multicall = IMulticall3(0xcA11bde05977b3631167028862bE2a173976CA11);

    // Array of existing WrappedDShare addresses 
    address[] wrappedDShareAddresses = [
        0x6bb71b2bdd892c5EfB960a76EDeC03b1F04551F4,
        0xF82F6801FA5Ab466C8820F08C9C7Adf893AC8d6F,
        0xF8C652054a60224E2d9c774Bfd118f6a27d5bCEf,
        0x3c5bEbe8998137E390b0cb791B42bF538353451b,
        0xADf3Cd8759Bd8bA9106342d1494b4Fb4b3720923,
        0x5bF7d0F8C178BB5b678Bf6bC20a2E499a85cFD4B,
        0x9deda619B8E208a2F2894502da3950b923521360
    ];

    function run() external {
        address owner = beacon.owner();
        console2.log("Beacon Owner:", owner);

        vm.startBroadcast(owner);

        console2.log("Current Beacon Implementation:", beacon.implementation());

        // Deploy new implementation with AccessControl
        WrappedDShare newImpl = new WrappedDShare();
        console2.log("New Implementation Deployed At:", address(newImpl));

        // Prepare Multicall3 calls
        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](wrappedDShareAddresses.length + 1);

        // Call 1: Upgrade the beacon
        calls[0] = IMulticall3.Call3({
            target: address(beacon),
            allowFailure: false,
            callData: abi.encodeWithSelector(UpgradeableBeacon.upgradeTo.selector, address(newImpl))
        });

        // Calls 2+: Grant DEFAULT_ADMIN_ROLE via initializeV2 for each WrappedDShare
        address roleRecipient = owner;
        for (uint256 i = 0; i < wrappedDShareAddresses.length; i++) {
            calls[i + 1] = IMulticall3.Call3({
                target: wrappedDShareAddresses[i],
                allowFailure: true,
                callData: abi.encodeWithSelector(WrappedDShare.initializeV2.selector, roleRecipient)
            });
        }

        // Execute Multicall3
        console2.log("Executing Multicall3...");
        (bool[] memory successes, bytes[] memory results) = multicall.aggregate3(calls);

        // Log results
        console2.log("Beacon Upgrade Success:", successes[0]);
        console2.log("Beacon Upgraded To:", beacon.implementation());

        for (uint256 i = 0; i < wrappedDShareAddresses.length; i++) {
            console2.log("WrappedDShare", i, "at:", wrappedDShareAddresses[i]);
            console2.log("initializeV2 Success:", successes[i + 1]);
            if (!successes[i + 1]) {
                console2.log("Failure Reason:", string(results[i + 1]));
            }
        }

        vm.stopBroadcast();
    }
}