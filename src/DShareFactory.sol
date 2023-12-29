// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {TransferRestrictor} from "./TransferRestrictor.sol";
import {DShare} from "./DShare.sol";
import {IDShareFactory} from "./IDShareFactory.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {CREATE3} from "solady/src/utils/CREATE3.sol";

///@notice Factory to create new dShares
///@author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/DShareFactory.sol)
contract DShareFactory is IDShareFactory {
    DShare public implementation;
    UpgradeableBeacon public beacon;
    TransferRestrictor public transferRestrictor;

    error ZeroAddress();
    error DeploymentRevert();

    event NewImplementSet(address indexed implementation);
    event NewTransferRestrictorSet(address indexed transferRestrictor);
    event NewBeaconSet(address indexed beacon);

    constructor(DShare _implementation, TransferRestrictor _transferRestrictor, UpgradeableBeacon _beacon) {
        if (
            address(_beacon) == address(0) || address(_transferRestrictor) == address(0)
                || address(_implementation) == address(0)
        ) revert ZeroAddress();
        implementation = _implementation;
        transferRestrictor = _transferRestrictor;
        beacon = _beacon;
    }

    /// @notice Sets a new implementation for the dShare
    /// @param _implementation New implementation
    function setNewImplementation(DShare _implementation) external {
        if (address(_implementation) == address(0)) revert ZeroAddress();
        implementation = _implementation;
        emit NewImplementSet(address(_implementation));
    }

    /// @notice Sets a new transfer restrictor for the dShare
    /// @param _transferRestrictor New transfer restrictor
    function setNewTransferRestrictor(TransferRestrictor _transferRestrictor) external {
        if (address(_transferRestrictor) == address(0)) revert ZeroAddress();
        transferRestrictor = _transferRestrictor;
        emit NewTransferRestrictorSet(address(_transferRestrictor));
    }

    /// @notice Sets a new beacon for the dShare
    /// @param _beacon New beacon
    function setNewBeacon(UpgradeableBeacon _beacon) external {
        if (address(_beacon) == address(0)) revert ZeroAddress();
        beacon = _beacon;
        emit NewBeaconSet(address(_beacon));
    }

    /// @notice Creates a new dShare
    /// @param owner of the proxy
    /// @param name Name of the dShare
    /// @param symbol Symbol of the dShare
    function createDShare(address owner, string memory name, string memory symbol) external {
        // slither-disable-next-line too-many-digits
        bytes memory bytecode = abi.encodePacked(
            type(BeaconProxy).creationCode,
            abi.encode(
                address(beacon),
                abi.encodeWithSelector(DShare.initialize.selector, owner, name, symbol, transferRestrictor)
            )
        );

        // Compute the salt with symbol
        bytes32 salt = keccak256(abi.encode(symbol));

        address predictedAddress = CREATE3.getDeployed(salt);

        address dShareAddress;

        dShareAddress = CREATE3.deploy(salt, bytecode, 0);

        // Check if the deployment was successful
        if (dShareAddress != predictedAddress) revert DeploymentRevert();

        emit DShareCreated(dShareAddress);
    }
}
