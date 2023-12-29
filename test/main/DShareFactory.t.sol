// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DShareFactory} from "../../src/DShareFactory.sol";
import {TransferRestrictor} from "../../src/TransferRestrictor.sol";
import {DShare} from "../../src/DShare.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";

contract DShareFactoryTest is Test {
    DShareFactory factory;
    TransferRestrictor restrictor;
    DShare tokenImplementation;
    UpgradeableBeacon beacon;

    event DShareCreated(address indexed dShare);
    event NewImplementSet(address indexed implementation);
    event NewTransferRestrictorSet(address indexed transferRestrictor);
    event NewBeaconSet(address indexed beacon);

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        tokenImplementation = new DShare();
        beacon = new UpgradeableBeacon(address(tokenImplementation), address(this));

        factory = new DShareFactory(tokenImplementation, restrictor, beacon);
    }

    function testDeployNewFactory() public {
        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        DShareFactory newFactory = new DShareFactory(DShare(address(0)), restrictor, beacon);

        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        newFactory = new DShareFactory(DShare(address(1)), TransferRestrictor(address(0)), beacon);

        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        newFactory = new DShareFactory(DShare(address(1)), restrictor, UpgradeableBeacon(address(0)));

        newFactory = new DShareFactory(tokenImplementation, restrictor, beacon);
    }

    function testSetter() public {
        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        factory.setNewImplementation(DShare(address(0)));

        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        factory.setNewTransferRestrictor(TransferRestrictor(address(0)));

        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        factory.setNewBeacon(UpgradeableBeacon(address(0)));

        vm.expectEmit(true, true, true, true);
        emit NewImplementSet(address(tokenImplementation));
        factory.setNewImplementation(tokenImplementation);
        vm.expectEmit(true, true, true, true);
        emit NewTransferRestrictorSet(address(restrictor));
        factory.setNewTransferRestrictor(restrictor);
        vm.expectEmit(true, true, true, true);
        emit NewBeaconSet(address(beacon));
        factory.setNewBeacon(beacon);
    }

    function testDeployNewDShareViaFactory() public {
        bytes memory bytecode = type(BeaconProxy).creationCode;
        bytecode = abi.encodePacked(
            bytecode,
            abi.encode(
                address(beacon),
                abi.encodeWithSelector(DShare.initialize.selector, address(this), "Dinari Token", "dTKN", restrictor)
            )
        );

        // Compute the salt the same way as in the createDShare function
        bytes32 salt = keccak256(abi.encode(bytecode, "Dinari Token"));

        // Calculate the predicted address the same way as in the createDShare function
        address predictedAddress = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(bytecode)))))
        );

        vm.expectEmit(true, true, true, true);
        emit DShareCreated(predictedAddress);
        factory.createDShare(address(this), "Dinari Token", "dTKN");
    }
}
