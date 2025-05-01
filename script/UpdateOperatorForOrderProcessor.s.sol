// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";

contract UpdateOperatorForOrderProcessor is Script {
    using stdJson for string;

    /**
     * @notice Script to update the Operator (FulfillmentRouter) address in OrderProcessor
     * @dev Prerequisites:
     *      1. This script must be run AFTER:
     *         - FulfillmentRouter is deployed (so its address is available in release_config)
     *         - OrderProcessor is deployed or upgraded
     *
     *      2. Environment Variables:
     *         - PRIVATE_KEY: (for signing transactions)
     *         - RPC_URL: (for connecting to the network)
     *         - ENVIRONMENT: Target environment (e.g., production, staging)
     *
     *      3. Required Files:
     *         - releases/v1.0.0/orderprocessor.json: Contains OrderProcessor address under .deployments.<environment>.<chainId>
     *         - release_config/<environment>/<chainId>.json: Contains the FulfillmentRouter address under .order_processor.fulfillment_router
     *
     * @dev Workflow:
     *      1. Loads the deployed address of OrderProcessor from releases/v1.0.0/orderprocessor.json
     *      2. Loads the new FulfillmentRouter address from release_config under .order_processor.fulfillment_router
     *      3. Checks if the address is already an operator in OrderProcessor
     *      4. If the address is already set as operator, do nothing
     *      5. Otherwise, updates OrderProcessor to set the new operator
     * @dev Run:
     *      forge script script/UpdateOperatorForOrderProcessor.s.sol:UpdateOperatorForOrderProcessor \
     *      --rpc-url $RPC_URL \
     *      --private-key $PRIVATE_KEY \
     *      --broadcast \
     *      --env ENVIRONMENT=<environment>
     */
    function run() external {
        // Get environment variables
        string memory environment = vm.envString("ENVIRONMENT");
        string memory chainId = vm.toString(block.chainid);

        // Construct the release config path: releases/v1.0.0/order_processor.json
        string memory releasePath = string.concat("releases/v1.0.0/order_processor.json");
        // Load the release JSON
        string memory releaseJson = vm.readFile(releasePath);

        // Construct the selector for the OrderProcessor address
        string memory selectorString = string.concat(".deployments.", environment, ".", chainId);
        address orderProcessorAddress = getAddressFromJson(releaseJson, selectorString);

        // Load the new FulfillmentRouter address from release_config under .order_processor.fulfillment_router
        string memory fulfillmentRouterPath = string.concat("releases/v1.0.0/fulfillment_router.json");
        string memory fulfillmentRouterJson = vm.readFile(fulfillmentRouterPath);
        string memory newFulfillmentRouterSelectorString = string.concat(".deployments.", environment, ".", chainId);
        address newFulfillmentRouter = getAddressFromJson(fulfillmentRouterJson, newFulfillmentRouterSelectorString);

        console2.log("OrderProcessor address: %s", orderProcessorAddress);
        console2.log("New FulfillmentRouter address (from config): %s", newFulfillmentRouter);

        // Check current operator status in OrderProcessor
        OrderProcessor orderProcessor = OrderProcessor(orderProcessorAddress);
        bool isCurrentOperator = orderProcessor.isOperator(newFulfillmentRouter);

        console2.log("Current operator status for FulfillmentRouter: %s", isCurrentOperator);

        // Compare and update operator if necessary
        if (isCurrentOperator) {
            console2.log("FulfillmentRouter is already set as operator. No action needed.");
        } else {
            console2.log("Setting new operator in OrderProcessor...");
            vm.startBroadcast();
            orderProcessor.setOperator(newFulfillmentRouter, true);
            vm.stopBroadcast();
            console2.log("Operator set successfully to %s", newFulfillmentRouter);

            // Verify the update
            bool updatedOperatorStatus = orderProcessor.isOperator(newFulfillmentRouter);
            require(updatedOperatorStatus, "Operator update verification failed");
            console2.log("Verified: FulfillmentRouter is now operator: %s", updatedOperatorStatus);
        }
    }

    function getAddressFromJson(string memory json, string memory selector) internal pure returns (address) {
        try vm.parseJsonAddress(json, selector) returns (address addr) {
            return addr;
        } catch {
            revert(string.concat("Failed to parse address from JSON: ", json));
        }
    }
}
