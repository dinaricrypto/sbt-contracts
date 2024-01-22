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

    event DShareCreated(address indexed dShare, string indexed symbol, string name);
    event NewTransferRestrictorSet(address indexed transferRestrictor);

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        tokenImplementation = new DShare();
        beacon = new UpgradeableBeacon(address(tokenImplementation), address(this));

        factory = new DShareFactory(beacon, restrictor);
    }

    function testDeployNewFactory() public {
        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        DShareFactory newFactory = new DShareFactory(beacon, TransferRestrictor(address(0)));

        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        newFactory = new DShareFactory(UpgradeableBeacon(address(0)), restrictor);

        newFactory = new DShareFactory(beacon, restrictor);
    }

    function testSetNewTransferRestrictor() public {
        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        factory.setNewTransferRestrictor(TransferRestrictor(address(0)));

        vm.expectEmit(true, true, true, true);
        emit NewTransferRestrictorSet(address(restrictor));
        factory.setNewTransferRestrictor(restrictor);
    }

    function testDeployNewDShareViaFactory(string memory name, string memory symbol) public {
        vm.expectEmit(false, false, false, false);
        emit DShareCreated(address(0), symbol, name);
        address newdshare = factory.createDShare(address(this), name, symbol);
        assertEq(DShare(newdshare).owner(), address(this));
        assertEq(DShare(newdshare).name(), name);
        assertEq(DShare(newdshare).symbol(), symbol);
        assertEq(address(DShare(newdshare).transferRestrictor()), address(restrictor));
    }
}
