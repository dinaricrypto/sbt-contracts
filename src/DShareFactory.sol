// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {TransferRestrictor} from "./TransferRestrictor.sol";
import {DShare} from "./DShare.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";

///@notice Factory to create new dShares
///@author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/DShareFactory.sol)
contract DShareFactory {
    UpgradeableBeacon public immutable beacon;
    TransferRestrictor public transferRestrictor;

    error ZeroAddress();

    /// @notice Emitted when a new dShare is created
    event DShareCreated(address indexed dShare, string indexed symbol, string name);
    event NewTransferRestrictorSet(address indexed transferRestrictor);

    constructor(UpgradeableBeacon _beacon, TransferRestrictor _transferRestrictor) {
        if (address(_beacon) == address(0) || address(_transferRestrictor) == address(0)) revert ZeroAddress();
        beacon = _beacon;
        transferRestrictor = _transferRestrictor;
    }

    /// @notice Sets a new transfer restrictor for the dShare
    /// @param _transferRestrictor New transfer restrictor
    function setNewTransferRestrictor(TransferRestrictor _transferRestrictor) external {
        if (address(_transferRestrictor) == address(0)) revert ZeroAddress();
        transferRestrictor = _transferRestrictor;
        emit NewTransferRestrictorSet(address(_transferRestrictor));
    }

    /// @notice Creates a new dShare
    /// @param owner of the proxy
    /// @param name Name of the dShare
    /// @param symbol Symbol of the dShare
    /// @return dShare Address of the new dShare
    function createDShare(address owner, string memory name, string memory symbol) external returns (address dShare) {
        dShare = address(
            new BeaconProxy(
                address(beacon), abi.encodeCall(DShare.initialize, (owner, name, symbol, transferRestrictor))
            )
        );

        emit DShareCreated(dShare, symbol, name);
    }
}
