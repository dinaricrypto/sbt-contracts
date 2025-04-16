// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {JsonUtils} from "./utils/JsonUtils.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";

contract Restrict is Script {
    using stdJson for string;

    /**
     * @notice Script to restrict an account in TransferRestrictor
     * @dev Prerequisites:
     *      1. This script must be run AFTER:
     *         - TransferRestrictor is deployed (so its address is available in releases)
     *      2. Environment Variables:
     *         - ACCOUNT_TO_RESTRICT environment variable is set to the account address to restrict
     *         - PRIVATE_KEY: (for signing transactions)
     *         - RPC_URL: (for connecting to the network)
     *         - ENVIRONMENT: Target environment (e.g., production)
     *       3. Required Files:
     *         - releases/v1.0.0/transfer_restrictor.json: Contains the TransferRestrictor address under .deployments.<environment>.<chainId>
     * @dev Workflow:
     *      1. Loads the TransferRestrictor address from releases/v1.0.0/transfer_restrictor.json
     *      2. Checks if the account is already blacklisted
     *      3. If the account is already blacklisted, logs a message and exits
     *      4. If the account is not blacklisted, restricts the account
     *      5. Logs the TransferRestrictor address and the restricted account
     * @dev Run:
     *      forge script script/Restrict.s.sol:Restrict \
     *      --rpc-url $RPC_URL \
     *      --private-key $PRIVATE_KEY \
     *      --broadcast \
     */
    function run() external {
        string memory environment = vm.envString("ENVIRONMENT");
        string memory chainId = vm.toString(block.chainid);
        string memory transferRestrictorPath = string.concat("releases/v1.0.0/transfer_restrictor.json");
        string memory transferRestrictorJson = vm.readFile(transferRestrictorPath);
        string memory transferRestrictorSelector = string.concat(".deployments.", environment, ".", chainId);
        address transferRestrictorAddress =
            JsonUtils.getAddressFromJson(vm, transferRestrictorJson, transferRestrictorSelector);
        address accountToRestrict = vm.envAddress("ACCOUNT_TO_RESTRICT");

        TransferRestrictor transferRestrictor = TransferRestrictor(transferRestrictorAddress);

        vm.startBroadcast();
        if (transferRestrictor.isBlacklisted(accountToRestrict)) {
            console2.log("Account is already blacklisted:", accountToRestrict);
        } else {
            transferRestrictor.restrict(accountToRestrict);
            console2.log("Account has been blacklisted:", accountToRestrict);
        }
        vm.stopBroadcast();
        console2.log("TransferRestrictor address:", transferRestrictorAddress);
    }
}
