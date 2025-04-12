// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {JsonUtils} from "./utils/JsonUtils.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";

contract UpdateVaultForOrderProcessor is Script {
    using stdJson for string;

    /**
     * @notice Script to update the Vault address in OrderProcessor
     * @dev Prerequisites:
     *      1. This script must be run AFTER:
     *         - VAULT is deployed (so its address is available in release_config)
     *         - OrderProcessor is deployed or upgraded
     *
     *      2. Environment Variables:
     *         - PRIVATE_KEY: (for signing transactions)
     *         - RPC_URL: (for connecting to the network)
     *         - ENVIRONMENT: Target environment (e.g., production, staging)
     *         - ORDER_PROCESSOR_ADDRESS: The address of the deployed OrderProcessor contract
     *
     *      3. Required Files:
     *         - release_config/{environment}/{chainId}.json: Contains the Vault address under .order_processor.vault
     *
     * @dev Workflow:
     *      1. Loads the deployed address of OrderProcessor from environment variables
     *      2. Loads the new Vault address from release_config under .order_processor.vault
     *      3. Checks the current Vault address in OrderProcessor
     *      4. If the current address matches the new Vault, do nothing
     *      5. Otherwise, updates OrderProcessor to use the new Vault
     * @dev Run:
     *      forge script script/UpdateVaultForOrderProcessor.s.sol:UpdateVaultForOrderProcessor \
     *      --rpc-url $RPC_URL \
     *      --private-key $PRIVATE_KEY \
     *      --broadcast \
     *      --env ENVIRONMENT=<environment> \
     *      --env ORDER_PROCESSOR_ADDRESS=<order_processor_address>
     */
    function run() external {
        // Get environment variables
        string memory environment = vm.envString("ENVIRONMENT");
        address orderProcessorAddress = vm.envAddress("ORDER_PROCESSOR_ADDRESS");
        uint256 chainId = block.chainid;

        // Load the new Vault address from release_config under .order_processor.vault
        string memory configPath = string.concat("release_config/", environment, "/", vm.toString(chainId), ".json");
        string memory configJson = vm.readFile(configPath);
        address newVaultAddress = _getAddressFromConfig(configJson, "OrderProcessor", "vault");

        require(newVaultAddress != address(0), "Vault address not found in config");

        // Load the deployed OrderProcessor address from environment
        require(orderProcessorAddress != address(0), "OrderProcessor address not found in environment");

        console2.log("OrderProcessor address: %s", orderProcessorAddress);
        console2.log("New Vault address (from config): %s", newVaultAddress);

        // Check current Vault in OrderProcessor
        OrderProcessor orderProcessor = OrderProcessor(orderProcessorAddress);
        address currentVault = orderProcessor.vault();

        console2.log("Current Vault in OrderProcessor: %s", currentVault);

        // Compare and update Vault if necessary
        if (currentVault == newVaultAddress) {
            console2.log("Vault is already up to date. No action needed.");
        } else {
            console2.log("Updating Vault in OrderProcessor...");
            vm.startBroadcast();
            orderProcessor.setVault(newVaultAddress);
            vm.stopBroadcast();
            console2.log("Vault updated successfully to %s", newVaultAddress);

            // Verify the update
            address updatedVault = orderProcessor.vault();
            require(updatedVault == newVaultAddress, "Vault update verification failed");
            console2.log("Verified: Vault in OrderProcessor is now %s", updatedVault);
        }
    }

    /**
     * @notice Loads an address from the release_config JSON file
     * @param configJson The JSON content of the config file
     * @param contractName The underscore-formatted name of the contract (e.g., "order_processor")
     * @param paramName The parameter name (e.g., "vault")
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
