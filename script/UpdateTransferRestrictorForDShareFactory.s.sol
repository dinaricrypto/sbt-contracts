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
     *         - ENVIRONMENT: Target environment (e.g., production, staging)
     *         - DSHARE_FACTORY_ADDRESS: The address of the deployed DShareFactory contract
     *
     *      3. Required Files:
     *         - release_config/{environment}/{chainId}.json: Contains the TransferRestrictor address under .dshare_factory.transferRestrictor
     *
     * @dev Workflow:
     *      1. Loads the deployed address of DShareFactory from environment variables
     *      2. Loads the new TransferRestrictor address from release_config under .dshare_factory.transferRestrictor
     *      3. Checks the current TransferRestrictor address in DShareFactory
     *      4. If the current address matches the new TransferRestrictor, do nothing
     *      5. Otherwise, updates DShareFactory to use the new TransferRestrictor
     * @dev Run:
     *      forge script script/UpdateTransferRestrictorForDShareFactory.s.sol:UpdateTransferRestrictorForDShareFactory \
     *      --rpc-url $RPC_URL \
     *      --private-key $PRIVATE_KEY \
     *      --broadcast \
     *      --env ENVIRONMENT=<environment>
     */
    function run() external {
        // Get environment variables
        string memory environment = vm.envString("ENVIRONMENT");
        address dshareFactoryAddress = vm.envAddress("DSHARE_FACTORY_ADDRESS");
        uint256 chainId = block.chainid;

        // Load the new TransferRestrictor address from release_config under .dshare_factory.transferRestrictor
        string memory configPath = string.concat("release_config/", environment, "/", vm.toString(chainId), ".json");
        string memory configJson = vm.readFile(configPath);
        address newTransferRestrictorAddress = _getAddressFromConfig(configJson, "DShareFactory", "transferRestrictor");

        require(newTransferRestrictorAddress != address(0), "TransferRestrictor address not found in config");

        // Load the deployed DShareFactory address from environment
        require(dshareFactoryAddress != address(0), "DShareFactory address not found in artifacts");

        console2.log("DShareFactory address: %s", dshareFactoryAddress);
        console2.log("New TransferRestrictor address (from config): %s", newTransferRestrictorAddress);

        // Check current TransferRestrictor in DShareFactory
        DShareFactory dshareFactory = DShareFactory(dshareFactoryAddress);
        address currentTransferRestrictor = dshareFactory.getTransferRestrictor();

        console2.log("Current TransferRestrictor in DShareFactory: %s", currentTransferRestrictor);

        // Compare and update if necessary
        if (currentTransferRestrictor == newTransferRestrictorAddress) {
            console2.log("TransferRestrictor is already up to date. No action needed.");
        } else {
            console2.log("Updating TransferRestrictor in DShareFactory...");
            vm.startBroadcast();
            dshareFactory.setNewTransferRestrictor(newTransferRestrictorAddress);
            vm.stopBroadcast();
            console2.log("TransferRestrictor updated successfully to %s", newTransferRestrictorAddress);

            // Verify the update
            address updatedTransferRestrictor = dshareFactory.getTransferRestrictor();
            require(
                updatedTransferRestrictor == newTransferRestrictorAddress,
                "TransferRestrictor update verification failed"
            );
            console2.log("Verified: TransferRestrictor in DShareFactory is now %s", updatedTransferRestrictor);
        }
    }

    /**
     * @notice Loads an address from the release_config JSON file
     * @param configJson The JSON content of the config file
     * @param contractName The underscore-formatted name of the contract (e.g., "dshare_factory")
     * @param paramName The parameter name (e.g., "transferRestrictor")
     * @return The address from the config
     */
    function _getAddressFromConfig(string memory configJson, string memory contractName, string memory paramName)
        internal
        pure
        returns (address)
    {
        string memory selector = string.concat(".", contractName, ".", paramName);
        return JsonUtils.getAddressFromJson(vm, configJson, selector);
    }
}
