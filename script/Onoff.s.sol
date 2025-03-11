// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {JsonUtils} from "./utils/JsonUtils.sol";
import {FulfillmentRouter} from "../src/orders/FulfillmentRouter.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {DShareFactory} from "../src/DShareFactory.sol";
import {Vault} from "../src/orders/Vault.sol";

/**
 * @notice Script for granting roles to specific accounts for deployed contracts
 * @dev This script manages role assignments for various contracts in the system
 *      Prerequisites:
 *      1. Environment Variables:
 *         - CONTRACT_NAME: Name of the contract to configure
 *         - VERSION: Version of the deployed contracts
 *         - ENVIRONMENT: Target environment (e.g., production, staging)
 *      2. Required Files:
 *         - releases/{version}/}{contract}.json: Deployment addresses
 *         - release_config/{environment}/{chainId}.json: Configuration data
 * @dev Workflow:
 *      1. Reads contract name, version, and environment from env variables
 *      2. Loads release and config data from JSON files
 *      3. Grants appropriate roles based on contract type
 * @dev Run example:
 *      forge script script/Onoff.s.sol:Onoff \
 *      --rpc-url $RPC_URL \
 *      --private-key $PRIVATE_KEY \
 *      --broadcast
 */
contract Onoff is Script {
    /**
     * @dev Main entry point for the script execution
     */
    function run() public {
        string memory contractName = vm.envString("CONTRACT_NAME");
        string memory version = vm.envString("VERSION");
        string memory environment = vm.envString("ENVIRONMENT");
        string memory releasePath = string.concat("releases/", version, "/", _getConfigName(contractName), ".json");
        string memory releaseJson = vm.readFile(releasePath);

        string memory configPath =
            string.concat("release_config/", environment, "/", vm.toString(block.chainid), ".json");
        string memory configJson = vm.readFile(configPath);

        vm.startBroadcast();
        _grantRole(configJson, releaseJson, environment, contractName);
        vm.stopBroadcast();
    }

    /**
     * @dev Maps contract names to their configuration file names
     * @param contractName Name of the contract
     * @return Config file name corresponding to the contract
     */
    function _getConfigName(string memory contractName) internal pure returns (string memory) {
        bytes32 inputHash = keccak256(bytes(contractName));

        if (inputHash == keccak256(bytes("TransferRestrictor"))) return "transfer_restrictor";
        if (inputHash == keccak256(bytes("DShareFactory"))) return "dshare_factory";
        if (inputHash == keccak256(bytes("DividendDistribution"))) return "dividend_distribution";
        if (inputHash == keccak256(bytes("DShare"))) return "dshare";
        if (inputHash == keccak256(bytes("WrappedDshare"))) return "wrapped_dshare";
        if (inputHash == keccak256(bytes("OrderProcessor"))) return "order_processer";
        if (inputHash == keccak256(bytes("FulfillmentRouter"))) return "fulfillment_router";
        if (inputHash == keccak256(bytes("Vault"))) return "vault";

        revert(string.concat("Unknown contract name: ", contractName));
    }

    /**
     * @dev Extracts address from initialization data JSON
     * @param json Configuration JSON
     * @param contractName Target contract name
     * @param paramName Parameter name to extract
     * @return Extracted address
     */
    function _getAddressFromInitData(string memory json, string memory contractName, string memory paramName)
        internal
        pure
        returns (address)
    {
        string memory selector = string.concat(".", contractName, ".", paramName);
        return JsonUtils.getAddressFromJson(vm, json, selector);
    }

    /**
     * @dev Gets deployed contract address from release JSON
     * @param releaseJson Release data JSON
     * @param environment Target environment
     * @param chainid Target chain ID
     * @return Deployed contract address
     */
    function _getAddressFromRelease(string memory releaseJson, string memory environment, string memory chainid)
        internal
        pure
        returns (address)
    {
        string memory selector = string.concat(".", "deployments", ".", environment, ".", chainid);
        return JsonUtils.getAddressFromJson(vm, releaseJson, selector);
    }

    /**
     * @dev Grants appropriate roles to the specified account based on contract type
     * @param configJson Configuration data
     * @param releaseJson Release data
     * @param environment Target environment
     * @param contractName Name of the contract to configure
     */
    function _grantRole(
        string memory configJson,
        string memory releaseJson,
        string memory environment,
        string memory contractName
    ) public {
        bytes32 nameHash = keccak256(bytes(contractName));
        address operator = _getAddressFromInitData(configJson, contractName, "operator");
        address contractAddress = _getAddressFromRelease(releaseJson, environment, vm.toString(block.chainid));
        if (nameHash == keccak256(bytes("TransferRestrictor"))) {
            TransferRestrictor restrictor = TransferRestrictor(contractAddress);
            restrictor.grantRole(restrictor.RESTRICTOR_ROLE(), operator);
        }

        if (nameHash == keccak256(bytes("Vault"))) {
            Vault vault = Vault(contractAddress);
            vault.grantRole(vault.OPERATOR_ROLE(), operator);
        }

        if (nameHash == keccak256(bytes("FulfillmentRouter"))) {
            FulfillmentRouter router = FulfillmentRouter(contractAddress);
            router.grantRole(router.OPERATOR_ROLE(), operator);
        }

        if (nameHash == keccak256(bytes("DividendDistribution"))) {
            DividendDistribution distribution = DividendDistribution(contractAddress);
            distribution.grantRole(distribution.DISTRIBUTOR_ROLE(), operator);
        }

        if (nameHash == keccak256(bytes("OrderProcessor"))) {
            OrderProcessor processor = OrderProcessor(contractAddress);
            processor.setOperator(operator, true);
        }

        revert(string.concat("Unknown contract name: ", contractName));
    }
}
