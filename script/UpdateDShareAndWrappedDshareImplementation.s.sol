// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpdateDShareAndWrappedDshareImplementation is Script {
    using stdJson for string;
    /**
     * @notice Script to update the implemnation address in DShare and WrappedDshare
     * @dev Prerequisites:
     *      1. This script must be run AFTER:
     *         - DShare and WrappedDshare Implementations are deployed
     *
     *      2. Environment Variables:
     *         - PRIVATE_KEY: (for signing transactions)
     *         - RPC_URL: (for connecting to the network)
     *         - ENVIRONMENT: Target environment (e.g., production)
     *
     *      3. Required Files:
     *         - releases/v0.3.1/dshare_beacon.json: Contains DshareBeacon address under .deployments.<environment>.<chainId>
     *         - releases/v0.3.1/wrapped_dshare_beacon.json: Contains the WrappedDshare address under .deployments.<environment>.<chainId>
     *         - script/utils/implementation.json: Contains the DShare and WrappedDshare implementation addresses
     *
     * @dev Workflow:
     *     1. Loads the DShare and WrappedDshare beacon addresses from releases/v0.3.1/dshare_beacon.json and releases/v0.3.1/wrapped_dshare_beacon.json
     *     2. Loads the DShare and WrappedDshare implementation addresses from script/utils/implementation.json
     *     3. Initializes the UpgradeableBeacon contracts for DShare and WrappedDshare
     *     4. Checks if the current implementation address in the beacon matches the new implementation address
     *     5. If the current implementation address is different, updates the beacon to the new implementation address
     *     6. If the current implementation address is the same, logs that no update is needed
     *     7. Logs the completion of the update process
     * @dev Run:
     *      forge script script/UpdateOperatorForOrderProcessor.s.sol:UpdateOperatorForOrderProcessor \
     *      --rpc-url $RPC_URL \
     *      --private-key $PRIVATE_KEY \
     *      --broadcast \
     */

    function run() external {
        // Get environment variables
        string memory environment = vm.envString("ENVIRONMENT");
        string memory chainId = vm.toString(block.chainid);

        // Get beacon and implementation addresses
        address dshareBeaconAddress =
            getJsonAddress(string.concat("releases/v0.3.1/dshare_beacon.json"), environment, chainId);
        address wrappedDshareBeaconAddress =
            getJsonAddress(string.concat("releases/v0.3.1/wrapped_dshare_beacon.json"), environment, chainId);
        address dshareImplementationAddress = getImplementationAddress(string.concat(".DShare.", chainId));
        address wrappedDshareImplementationAddress = getImplementationAddress(string.concat(".WrappedDShare.", chainId));

        // Initialize beacon contracts
        UpgradeableBeacon dshareBeacon = UpgradeableBeacon(dshareBeaconAddress);
        UpgradeableBeacon wrappedDshareBeacon = UpgradeableBeacon(wrappedDshareBeaconAddress);

        // Update DShare beacon implementation
        vm.startBroadcast();
        if (dshareBeacon.implementation() != dshareImplementationAddress) {
            console2.log("Updating DShare beacon implementation to:", dshareImplementationAddress);
            dshareBeacon.upgradeTo(dshareImplementationAddress);
        } else {
            console2.log("DShare beacon already has the latest implementation:", dshareImplementationAddress);
        }

        // Update WrappedDShare beacon implementation
        if (wrappedDshareBeacon.implementation() != wrappedDshareImplementationAddress) {
            console2.log("Updating WrappedDShare beacon implementation to:", wrappedDshareImplementationAddress);
            wrappedDshareBeacon.upgradeTo(wrappedDshareImplementationAddress);
        } else {
            console2.log(
                "WrappedDShare beacon already has the latest implementation:", wrappedDshareImplementationAddress
            );
        }
        vm.stopBroadcast();
        console2.log("DShare and WrappedDShare implementation update completed.");
    }

    function getJsonAddress(string memory path, string memory environment, string memory chainId)
        internal
        view
        returns (address)
    {
        string memory json = vm.readFile(path);
        string memory selector = string.concat(".deployments.", environment, ".", chainId);
        try vm.parseJsonAddress(json, selector) returns (address addr) {
            return addr;
        } catch {
            revert(string.concat("Failed to parse address from JSON: ", json));
        }
    }

    // Get DShare implementation address from JSON
    function getImplementationAddress(string memory selector) internal view returns (address) {
        string memory implementationPath = string.concat("script/utils/implementation.json");
        string memory implementationJson = vm.readFile(implementationPath);
        try vm.parseJsonAddress(implementationJson, selector) returns (address addr) {
            return addr;
        } catch {
            revert(string.concat("Failed to parse address from JSON: ", implementationJson));
        }
    }
}
