// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {DShare} from "../../../src/DShare.sol";
import {TransferRestrictor} from "../../../src/TransferRestrictor.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract MockDShareFactory {
    DShare public implementation;
    TransferRestrictor public transferRestrictor;
    UpgradeableBeacon public beacon;

    constructor() {
        implementation = new DShare();
        transferRestrictor = new TransferRestrictor(msg.sender);
        beacon = new UpgradeableBeacon(address(implementation), msg.sender);
    }

    function deploy(string memory name, string memory symbol) external returns (DShare) {
        return DShare(
            address(
                new BeaconProxy(
                    address(beacon), abi.encodeCall(DShare.initialize, (msg.sender, name, symbol, transferRestrictor))
                )
            )
        );
    }
}
