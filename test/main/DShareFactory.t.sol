// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DShareFactory} from "../../src/DShareFactory.sol";
import {TransferRestrictor} from "../../src/TransferRestrictor.sol";
import {DShare} from "../../src/DShare.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {CREATE3} from "solady/src/utils/CREATE3.sol";

contract DShareFactoryTest is Test {
    DShareFactory factory;
    TransferRestrictor restrictor;
    DShare tokenImplementation;
    UpgradeableBeacon beacon;

    event DShareCreated(address indexed dShare);
    event NewTransferRestrictorSet(address indexed transferRestrictor);
    event NewBeaconSet(address indexed beacon);

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        tokenImplementation = new DShare();
        beacon = new UpgradeableBeacon(address(tokenImplementation), address(this));

        factory = new DShareFactory(restrictor, beacon);
    }

    function testDeployNewFactory() public {
        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        DShareFactory newFactory = new DShareFactory(TransferRestrictor(address(0)), beacon);

        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        newFactory = new DShareFactory(restrictor, UpgradeableBeacon(address(0)));

        newFactory = new DShareFactory(restrictor, beacon);
    }

    function testSetter() public {
        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        factory.setNewTransferRestrictor(TransferRestrictor(address(0)));

        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        factory.setNewBeacon(UpgradeableBeacon(address(0)));

        vm.expectEmit(true, true, true, true);
        emit NewTransferRestrictorSet(address(restrictor));
        factory.setNewTransferRestrictor(restrictor);
        vm.expectEmit(true, true, true, true);
        emit NewBeaconSet(address(beacon));
        factory.setNewBeacon(beacon);
    }

    function testDeployNewDShareViaFactory(string memory symbol) public {
        bytes memory bytecode = type(BeaconProxy).creationCode;
        bytecode = abi.encodePacked(
            bytecode,
            abi.encode(
                address(beacon),
                abi.encodeWithSelector(DShare.initialize.selector, address(this), "Dinari Token", symbol, restrictor)
            )
        );

        // Compute the salt the same way as in the createDShare function
        bytes32 salt = keccak256(abi.encode(symbol));

        address predictedAddress = CREATE3.getDeployed(salt, address(factory));

        vm.expectEmit(true, true, true, true);
        emit DShareCreated(predictedAddress);
        factory.createDShare(address(this), "Dinari Token", symbol);
    }
}
