// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";

contract UpdateVaultForOrderProcessor is Script {
    using stdJson for string;

    /**
     * @notice Script to update the Vault address in OrderProcessor
     * @dev Prerequisites:
     *      1. This script must be run AFTER:
     *         - VAULT is deployed (so its address is available in releases)
     *         - OrderProcessor is deployed or upgraded
     *
     *      2. Environment Variables:
     *         - PRIVATE_KEY: (for signing transactions)
     *         - RPC_URL: (for connecting to the network)
     *         - ENVIRONMENT: Target environment (e.g., production)
     *
     *      3. Required Files:
     *         - releases/v1.0.0/{contracts}.json, contains the vault and orderprocessor addresses
     *
     * @dev Workflow:
     *      1. Loads the deployed address of OrderProcessor and the new Vault address
     *      2. Checks the current Vault address in OrderProcessor
     *      3. If the current address matches the new Vault, do nothing
     *      4. Otherwise, updates OrderProcessor to use the new Vault
     * @dev Run:
     *      forge script script/UpdateVaultForOrderProcessor.s.sol:UpdateVaultForOrderProcessor \
     *      --rpc-url $RPC_URL \
     *      --private-key $PRIVATE_KEY \
     *      --broadcast \
     */
    function run() external {
        // Get environment variables
        string memory environment = vm.envString("ENVIRONMENT");
        uint256 chainId = block.chainid;

        string memory orderProcessorPath = string.concat("releases/v1.0.0/order_processor.json");
        string memory orderProcessorJson = vm.readFile(orderProcessorPath);
        string memory orderProcessorSelector = string.concat(".deployments.", environment, ".", vm.toString(chainId));
        address orderProcessorAddress = getAddressFromJson(orderProcessorJson, orderProcessorSelector);

        // Load the new Vault addresson
        // Load the release JSON
        string memory vaultPath = string.concat("releases/v1.0.0/vault.json");
        string memory vaultJson = vm.readFile(vaultPath);
        string memory vaultSelector = string.concat(".deployments.", environment, ".", vm.toString(chainId));
        address vaultAddress = getAddressFromJson(vaultJson, vaultSelector);

        OrderProcessor orderProcessor = OrderProcessor(orderProcessorAddress);
        address currentVault = orderProcessor.vault();

        vm.startBroadcast();
        if (currentVault != vaultAddress) {
            console2.log("Updating vault in OrderProcessor");
            orderProcessor.setVault(vaultAddress);
        } else {
            console2.log("Vault is already up to date. No action needed.");
        }

        vm.stopBroadcast();
    }

    function getAddressFromJson(string memory json, string memory selector) internal pure returns (address) {
        try vm.parseJsonAddress(json, selector) returns (address addr) {
            return addr;
        } catch {
            revert(string.concat("Failed to parse address from JSON: ", json));
        }
    }
}
