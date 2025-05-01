// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {Vault} from "../src/orders/Vault.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract RescueERC20 is Script {
    using stdJson for string;

    /**
     * @notice Script to transfer ERC20 token from old Vault to new Vault
     * @dev Prerequisites:
     *      1. This script must be run AFTER:
     *         - New Vault is deployed (so its address is available in releases)
     *         - Old Vault (v0.3.1) is deployed (so its address is available in releases)
     *         - Caller has DEFAULT_ADMIN_ROLE
     *
     *      2. Environment Variables:
     *         - PRIVATE_KEY: (for signing transactions)
     *         - RPC_URL: (for connecting to the network)
     *         - ENVIRONMENT: Target environment (e.g., production, staging)
     *
     *      3. Required Files:
     *         - script/utils/mainnet_token.json: Contains the token address to rescue
     *         - release_config/{environment}/{chainId}.json: Contains the OrderProcessor address under .order_processor.address
     *
     * @dev Workflow:
     *      1. Load the deployed vault from v0.3.1 and v1.0.0
     *      2. Loads the token address
     *      3. Calls the rescueERC20 function on Vault to transfer tokens from old vault to new vault
     */
    function run() external {
        // Get environment variables
        string memory environment = vm.envString("ENVIRONMENT");
        string memory chainId = vm.toString(block.chainid);

        // Get token to rescue
        string memory tokenPath = string.concat("script/utils/mainnet_token.json");
        string memory tokenJson = vm.readFile(tokenPath);
        string memory tokenSelector = chainId;
        address token;
        try vm.parseJsonAddress(tokenJson, tokenSelector) returns (address t) {
            token = t;
        } catch {
            revert("Failed to parse token address from JSON");
        }

        // get new vault address (version 1.0.0)
        string memory newVaultPath = string.concat("releases/v1.0.0/vault.json");
        string memory newVaultJson = vm.readFile(newVaultPath);
        string memory selectorString = string.concat(".deployments.", environment, ".", chainId);
        address newVaultAddress = getAddressFromJson(newVaultJson, selectorString);

        // get last deployed vault (version 0.3.1)
        string memory oldVaultPath = string.concat("releases/v0.3.1/vault.json");
        string memory oldVaultJson = vm.readFile(oldVaultPath);
        address oldVaultAddress = getAddressFromJson(oldVaultJson, selectorString);

        // get contract instance
        Vault oldVault = Vault(oldVaultAddress);
        uint256 amount = IERC20(token).balanceOf(oldVaultAddress);

        vm.startBroadcast();

        if (amount > 0) {
            console2.log("Transferring %s tokens from old vault to new vault", amount);
            oldVault.rescueERC20(IERC20(token), newVaultAddress, amount);
        } else {
            console2.log("No tokens to transfer from old vault");
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
