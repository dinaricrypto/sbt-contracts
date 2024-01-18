// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {DShare} from "../../../src/DShare.sol";
import {TransferRestrictor} from "../../../src/TransferRestrictor.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {MockLayerZeroEndpoint} from "./MockLayerZeroEndpoint.sol";

contract MockDShareFactory {
    DShare public implementation;
    TransferRestrictor public transferRestrictor;
    UpgradeableBeacon public beacon;
    MockLayerZeroEndpoint public lzEndpoint;

    constructor() {
        implementation = new DShare();
        transferRestrictor = new TransferRestrictor(msg.sender);
        beacon = new UpgradeableBeacon(address(implementation), msg.sender);
        lzEndpoint = new MockLayerZeroEndpoint();
    }

    function deploy(string memory name, string memory symbol) external returns (DShare) {
        return DShare(
            address(
                new BeaconProxy(
                    address(beacon),
                    abi.encodeCall(
                        DShare.initialize, (msg.sender, name, symbol, transferRestrictor, address(lzEndpoint))
                    )
                )
            )
        );
    }
}
