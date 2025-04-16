// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {JsonUtils} from "./utils/JsonUtils.sol";
import {DShareFactory} from "../src/DShareFactory.sol";

contract UpdateTransferRestrictorForDShareFactory is Script {
    using stdJson for string;

    /**
     * @notice Script to update the TransferRestrictor address in DShareFactory
     * @dev Prerequisites:
     *      1. This script must be run AFTER:
     *         - TRANSFER_RESTRICTOR is deployed (so its address is available in release_config)
     *         - DShareFactory is upgraded
     *
     *      2. Environment Variables:
     *         - PRIVATE_KEY: (for signing transactions)
     *         - RPC_URL: (for connecting to the network)
     *         - ENVIRONMENT: Target environment (e.g., production)
     *
     *      3. Required Files:
     *         - releases/v1.0.0/ Contains the new TransferRestrictor and updated DShareFactory addresses
     *
     * @dev Workflow:
     *      1. Loads the deployed addresses
     *      2. Checks the current TransferRestrictor address in DShareFactory
     *      4. If the current address matches the new TransferRestrictor, do nothing
     *      5. Otherwise, updates DShareFactory to use the new TransferRestrictor
     * @dev Run:
     *      forge script script/UpdateTransferRestrictorForDShareFactory.s.sol:UpdateTransferRestrictorForDShareFactory \
     *      --rpc-url $RPC_URL \
     *      --private-key $PRIVATE_KEY \
     *      --broadcast \
     */
    function run() external {
        // Get environment variables
        string memory environment = vm.envString("ENVIRONMENT");
        uint256 chainId = block.chainid;

        // Construct the release config path: releases/v1.0.0/dshare_factory.json
        // Load the release JSON
        string memory dshareFactoryPath = string.concat("releases/v1.0.0/dshare_factory.json");
        string memory dshareFactoryJson = vm.readFile(dshareFactoryPath);
        string memory dshareFactorySelector = string.concat(".deployments.", environment, ".", vm.toString(chainId));
        address dshareFactoryAddress = JsonUtils.getAddressFromJson(vm, dshareFactoryJson, dshareFactorySelector);

        // Load new transferRestrictor address
        string memory transferRestrictorPath = string.concat("releases/v1.0.0/transfer_restrictor.json");
        string memory transferRestrictorJson = vm.readFile(transferRestrictorPath);
        string memory transferRestrictorSelector =
            string.concat(".deployments.", environment, ".", vm.toString(chainId));
        address newTransferRestrictorAddress =
            JsonUtils.getAddressFromJson(vm, transferRestrictorJson, transferRestrictorSelector);

        DShareFactory dshareFactory = DShareFactory(dshareFactoryAddress);
        address currentTransferRestrictor = dshareFactory.getTransferRestrictor();

        vm.startBroadcast();
        if (currentTransferRestrictor != newTransferRestrictorAddress) {
            console2.log("Updating TransferRestrictor in DShareFactory");
            dshareFactory.setNewTransferRestrictor(newTransferRestrictorAddress);
        } else {
            console2.log("TransferRestrictor is already up to date. No action needed.");
        }
        vm.stopBroadcast();
    }
}
