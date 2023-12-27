// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {TransferRestrictor} from "./TransferRestrictor.sol";
import {DShare} from "./DShare.sol";
import {IDShareFactory} from "./IDShareFactory.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";

contract DShareFactory is IDShareFactory {
    DShare public implementation;
    UpgradeableBeacon public beacon;
    TransferRestrictor public transferRestrictor;

    error InvalidImplementation();
    error InvalidTransferRestrictor();
    error InvalidBeacon();
    error DeploymentRevert();

    event NewImplementSet(address indexed newImplementation);
    event NewTransferRestrictorSet(address indexed newTransferRestrictor);
    event NewBeaconSet(address indexed newBeacon);

    constructor(DShare _implementation, TransferRestrictor _transferRestrictor, UpgradeableBeacon _beacon) {
        if (address(_beacon) == address(0)) revert InvalidBeacon();
        if (address(_transferRestrictor) == address(0)) revert InvalidTransferRestrictor();
        if (address(_implementation) == address(0)) revert InvalidImplementation();
        implementation = _implementation;
        transferRestrictor = _transferRestrictor;
        beacon = _beacon;
    }

    //
    function setNewImplementation(DShare _implementation) external {
        if (address(_implementation) == address(0)) revert InvalidImplementation();
        implementation = _implementation;
        emit NewImplementSet(address(_implementation));
    }

    function setNewTransferRestrictor(TransferRestrictor _transferRestrictor) external {
        if (address(_transferRestrictor) == address(0)) revert InvalidTransferRestrictor();
        transferRestrictor = _transferRestrictor;
        emit NewTransferRestrictorSet(address(_transferRestrictor));
    }

    function setNewBeacon(UpgradeableBeacon _beacon) external {
        if (address(_beacon) == address(0)) revert InvalidBeacon();
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

        // Compute the salt with owner, name and symbol
        bytes32 salt = keccak256(abi.encode(bytecode, name));

        // Predicted address
        address predictedAddress = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        address dShareAddress;

        assembly {
            dShareAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        // Check if the deployment was successful
        if (dShareAddress != predictedAddress) revert DeploymentRevert();

        emit DShareCreated(dShareAddress);
    }
}
