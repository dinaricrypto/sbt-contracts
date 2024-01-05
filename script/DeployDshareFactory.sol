// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {DShareFactory} from "../../src/DShareFactory.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CREATE3} from "solady/src/utils/CREATE3.sol";

contract DeployDshareFactory is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        TransferRestrictor restrictor = TransferRestrictor(vm.envAddress("RESTRICTOR"));
        UpgradeableBeacon beacon = UpgradeableBeacon(vm.envAddress("BEACON"));

        bytes memory bytecode = abi.encodePacked(
            type(DShareFactory).creationCode,
            abi.encode(restrictor, beacon)
        );

        bytes32 salt = keccak256(abi.encode(restrictor, beacon));
        
        vm.startBroadcast(deployerPrivateKey);
        CREATE3.deploy(salt, bytecode, 0);
        vm.stopBroadcast();

    }
}
