// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

// import {Script} from "forge-std/Script.sol";
// import {stdJson} from "forge-std/StdJson.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import {ControlledUpgradeable} from "../src/deployment/ControlledUpgradeable.sol";
// import {console} from "forge-std/console.sol";
// import {console2} from "forge-std/console2.sol";

// import {VmSafe} from "forge-std/Vm.sol";

// interface IVersioned {
//     // The version function that must be implemented by the inheriting contract
//     function publicVersion() external view returns (string memory);
// }

// contract DeployManager is Script {
//     using stdJson for string;

//     /**
//      * @notice Main deployment script for handling new deployments and upgrades
//      * @dev Prerequisites:
//      *      1. Environment Variables:
//      *         - CONTRACT: Name of contract to deploy
//      *         - VERSION: Current version being deployed
//      *         - ENVIRONMENT: Target environment (e.g., production, staging)
//      *         - DEPLOYED_VERSION: (Optional) Previous version for upgrades
//      *
//      *      2. Required Files:
//      *         - release_config/{environment}/{chainId}.json: Contract initialization params
//      *
//      * @dev Workflow:
//      *      1. Loads configuration and parameters from environment and JSON files
//      *      2. Checks for previous deployment address
//      *      3. If no previous deployment (address(0)):
//      *         - Deploys new implementation and proxy
//      *      4. If previous deployment exists:
//      *         - Checks version difference
//      *         - Upgrades if version changed or previous version not available
//      *      5. Writes deployment result to temp/{environment}/{chainId}.{contractName}.json
//      */
//     function run() external {
//         // Get params
//         address proxyAddress;
//         string memory deployedVersion;
//         string memory contractName = vm.envString("CONTRACT");
//         string memory normalizeContractName = _normalizeContractName(contractName);
//         string memory currentVersion = vm.envString("VERSION");
//         string memory environment = vm.envString("ENVIRONMENT");
//         string memory configPath =
//             string.concat("release_config/", environment, "/", vm.toString(block.chainid), ".json");
//         string memory configJson = vm.readFile(configPath);
//         bytes memory initParams = configJson.parseRaw(string.concat(".", normalizeContractName));

//         try vm.envString("DEPLOYED_VERSION") returns (string memory v) {
//             deployedVersion = v;
//         } catch {
//             deployedVersion = "";
//         }

//         vm.startBroadcast();

//         address previousDeploymentAddress =
//             _getPreviousDeploymentAddress(contractName, deployedVersion, environment, block.chainid);

//         if (previousDeploymentAddress == address(0)) {
//             console2.log("No previous deployment found for %s", normalizeContractName);
//             // Deploy new contract
//             proxyAddress =
//                 _deployContract(normalizeContractName, _getInitData(normalizeContractName, initParams, false));
//         } else {
//             string memory previousVersion;
//             // Get the previous version of the contract
//             try IVersioned(previousDeploymentAddress).publicVersion() returns (string memory v) {
//                 previousVersion = v;
//             } catch {}
//             if (
//                 keccak256(bytes(previousVersion)) != keccak256(bytes(currentVersion))
//                     || bytes(previousVersion).length == 0
//             ) {
//                 // Upgrade existing contract
//                 proxyAddress = _upgradeContract(
//                     normalizeContractName,
//                     previousDeploymentAddress,
//                     _getInitData(normalizeContractName, initParams, true)
//                 );
//             }
//         }

//         vm.stopBroadcast();

//         // Write result to chain-specific file
//         _writeDeployment(environment, block.chainid, contractName, proxyAddress);
//     }

//     function _getInitData(string memory contractName, bytes memory params, bool isUpgrade)
//         internal
//         pure
//         returns (bytes memory)
//     {
//         bytes32 nameHash = keccak256(bytes(contractName));
//         if (nameHash == keccak256(bytes("DShareFactory"))) {
//             return _getInitDataForDShareFactory(params, isUpgrade);
//         }
//         if (nameHash == keccak256(bytes("TransferRestrictor"))) {
//             return _getInitDataForTransferRestrictor(params, isUpgrade);
//         }
//         if (nameHash == keccak256(bytes("FulfillmentRouter"))) {
//             return _getInitDataForFulfillmentRouter(params, isUpgrade);
//         }
//         if (nameHash == keccak256(bytes("Vault"))) {
//             return _getInitDataForVault(params, isUpgrade);
//         }
//         if (nameHash == keccak256(bytes("OrderProcessor"))) {
//             return _getInitDataForOrderProcessor(params, isUpgrade);
//         }
//         if (nameHash == keccak256(bytes("DividendDistribution"))) {
//             return _getInitDataForDividendDistribution(params, isUpgrade);
//         }
//         revert(string.concat("Unsupported contract: ", contractName));
//     }

//     function _getInitDataForOrderProcessor(bytes memory params, bool isUpgrade) private pure returns (bytes memory) {
//         if (isUpgrade) {
//             address upgrader = abi.decode(params, (address));
//             return abi.encodeWithSignature("reinitialize(address)", upgrader);
//         }
//         (address owner, address treasury, address vault, address dShareFactory, address upgrader) =
//             abi.decode(params, (address, address, address, address, address));
//         return abi.encodeWithSignature(
//             "initialize(address,address,address,address,address)", owner, treasury, vault, dShareFactory, upgrader
//         );
//     }

//     function _getInitDataForDshare(bytes memory params, bool isUpgrade) private pure returns (bytes memory) {
//         if (isUpgrade) {
//             address upgrader = abi.decode(params, (address));
//             return abi.encodeWithSignature("reinitialize(address)", upgrader);
//         }
//         (address owner, address upgrader, string memory name, string memory symbol, address transferRestrictor) =
//             abi.decode(params, (address, address, string, string, address));
//         return abi.encodeWithSignature(
//             "initialize(address,address,string,string,address)", owner, upgrader, name, symbol, transferRestrictor
//         );
//     }

//     function _getInitDataForWrappedDshare(bytes memory params, bool isUpgrade) private pure returns (bytes memory) {
//         if (isUpgrade) {
//             address upgrader = abi.decode(params, (address));
//             return abi.encodeWithSignature("reinitialize(address)", upgrader);
//         }
//         (address owner, address upgrader, address dshare, string memory name, string memory symbol) =
//             abi.decode(params, (address, address, address, string, string));
//         return abi.encodeWithSignature(
//             "initialize(address,address,address,string,string)", owner, upgrader, dshare, name, symbol
//         );
//     }

//     function _getInitDataForDShareFactory(bytes memory params, bool isUpgrade) private pure returns (bytes memory) {
//         if (isUpgrade) {
//             address upgrader = abi.decode(params, (address));
//             return abi.encodeWithSignature("reinitialize(address)", upgrader);
//         }
//         (address owner, address dShareBeacon, address wrappedDShareBeacon, address transferRestrictor, address upgrader)
//         = abi.decode(params, (address, address, address, address, address));
//         return abi.encodeWithSignature(
//             "initialize(address,address,address,address,address)",
//             owner,
//             dShareBeacon,
//             wrappedDShareBeacon,
//             transferRestrictor,
//             upgrader
//         );
//     }

//     function _getInitDataForDividendDistribution(bytes memory params, bool isUpgrade)
//         private
//         pure
//         returns (bytes memory)
//     {
//         if (isUpgrade) {
//             address upgrader = abi.decode(params, (address));
//             return abi.encodeWithSignature("reinitialize(address)", upgrader);
//         }
//         (address owner, address upgrader) = abi.decode(params, (address, address));
//         return abi.encodeWithSignature("initialize(address,address)", owner, upgrader);
//     }

//     function _getInitDataForTransferRestrictor(bytes memory params, bool isUpgrade)
//         private
//         pure
//         returns (bytes memory)
//     {
//         if (isUpgrade) {
//             address upgrader = abi.decode(params, (address));
//             return abi.encodeWithSignature("reinitialize(address)", upgrader);
//         }
//         (address owner, address upgrader) = abi.decode(params, (address, address));
//         return abi.encodeWithSignature("initialize(address,address)", owner, upgrader);
//     }

//     function _getInitDataForFulfillmentRouter(bytes memory params, bool isUpgrade)
//         private
//         pure
//         returns (bytes memory)
//     {
//         if (isUpgrade) {
//             address upgrader = abi.decode(params, (address));
//             return abi.encodeWithSignature("reinitialize(address)", upgrader);
//         }
//         (address owner, address upgrader) = abi.decode(params, (address, address));
//         return abi.encodeWithSignature("initialize(address,address)", owner, upgrader);
//     }

//     function _getInitDataForVault(bytes memory params, bool isUpgrade) private pure returns (bytes memory) {
//         if (isUpgrade) {
//             address upgrader = abi.decode(params, (address));
//             return abi.encodeWithSignature("reinitialize(address)", upgrader);
//         }
//         (address owner, address upgrader) = abi.decode(params, (address, address));
//         return abi.encodeWithSignature("initialize(address,address)", owner, upgrader);
//     }

//     function _deployContract(string memory contractName, bytes memory initData) internal returns (address) {
//         address implementation = _deployImplementation(contractName);
//         ERC1967Proxy proxy = new ERC1967Proxy(implementation, initData);
//         console.log("Deployed %s at %s", contractName, address(proxy));
//         return address(proxy);
//     }

//     function _upgradeContract(string memory contractName, address proxyAddress, bytes memory upgradeData)
//         internal
//         returns (address)
//     {
//         address implementation = _deployImplementation(contractName);
//         if (upgradeData.length > 0) {
//             ControlledUpgradeable(payable(proxyAddress)).upgradeToAndCall(implementation, upgradeData);
//         } else {
//             revert("Upgrade data not provided");
//         }
//         console.log("Upgraded %s at %s", contractName, proxyAddress);
//         return proxyAddress;
//     }

//     // Helper functions remain similar to previous implementation
//     function _deployImplementation(string memory contractName) internal returns (address) {
//         bytes memory creationCode = vm.getCode(string.concat(contractName, ".sol:", contractName));
//         require(creationCode.length > 0, string.concat("Contract code not found: ", contractName));

//         address implementation;
//         assembly {
//             implementation := create(0, add(creationCode, 0x20), mload(creationCode))
//         }
//         require(implementation != address(0), "Implementation deployment failed");
//         return implementation;
//     }

//     function _getPreviousDeploymentAddress(
//         string memory contractName,
//         string memory deployedVersion,
//         string memory environment,
//         uint256 chainId
//     ) internal returns (address) {
//         if (bytes(deployedVersion).length == 0) return address(0);

//         string memory deployedPath = string.concat("releases/", deployedVersion, "/", contractName, ".json");
//         if (!vm.exists(deployedPath)) return address(0);

//         try vm.parseJsonAddress(
//             vm.readFile(deployedPath), string.concat(".deployments.", environment, ".", vm.toString(chainId))
//         ) returns (address addr) {
//             return addr;
//         } catch {
//             return address(0);
//         }
//     }

//     function _writeDeployment(
//         string memory environment,
//         uint256 chainId,
//         string memory contractName,
//         address deployedAddress
//     ) internal {
//         // Create artifact directory structure
//         string memory tempDir = "artifact";
//         string memory tempEnvDir = string.concat(tempDir, "/", environment);

//         if (!vm.exists(tempDir)) {
//             vm.createDir(tempDir, true);
//         }
//         if (!vm.exists(tempEnvDir)) {
//             vm.createDir(tempEnvDir, true);
//         }

//         // Create deployment file under artifact/environment/chainId.contractName.json
//         string memory deploymentPath =
//             string.concat(tempDir, "/", environment, "/", vm.toString(chainId), ".", contractName, ".json");

//         string memory json = vm.serializeAddress("{}", "address", deployedAddress);
//         vm.writeFile(deploymentPath, json);

//         console2.log("Deployment written to:", deploymentPath);
//     }

//     function _normalizeContractName(string memory input) private pure returns (string memory) {
//         bytes32 inputHash = keccak256(bytes(input));

//         if (inputHash == keccak256(bytes("transfer_restrictor"))) return "TransferRestrictor";
//         if (inputHash == keccak256(bytes("dshare_factory"))) return "DShareFactory";
//         if (inputHash == keccak256(bytes("order_processor"))) return "OrderProcessor";
//         if (inputHash == keccak256(bytes("dividend_distributor"))) return "DividendDistributor";
//         if (inputHash == keccak256(bytes("dshare"))) return "Dshare";
//         if (inputHash == keccak256(bytes("wrapped_dshare"))) return "WrappedDshare";
//         if (inputHash == keccak256(bytes("fulfillment_router"))) return "FulfillmentRouter";
//         if (inputHash == keccak256(bytes("vault"))) return "Vault";

//         revert(string.concat("Unknown contract name: ", input));
//     }
// }
