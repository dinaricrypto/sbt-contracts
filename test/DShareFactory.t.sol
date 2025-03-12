// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DShareFactory} from "../src/DShareFactory.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {DShare} from "../src/DShare.sol";
import {WrappedDShare} from "../src/WrappedDShare.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract DShareFactoryTest is Test {
    DShareFactory factory;
    TransferRestrictor restrictor;
    UpgradeableBeacon beacon;
    UpgradeableBeacon wrappedBeacon;

    event DShareAdded(address indexed dShare, address indexed wrappedDShare, string indexed symbol, string name);
    event NewTransferRestrictorSet(address indexed transferRestrictor);

    address user = address(0x1);
    address upgrader = address(0x2);

    function setUp() public {
        TransferRestrictor restrictorImpl = new TransferRestrictor();
        restrictor = TransferRestrictor(
            address(
                new ERC1967Proxy(
                    address(restrictorImpl), abi.encodeCall(restrictorImpl.initialize, (address(this), upgrader))
                )
            )
        );
        DShare tokenImplementation = new DShare();
        beacon = new UpgradeableBeacon(address(tokenImplementation), address(this));
        WrappedDShare wrappedTokenImplementation = new WrappedDShare();
        wrappedBeacon = new UpgradeableBeacon(address(wrappedTokenImplementation), address(this));

        DShareFactory factoryImpl = new DShareFactory();
        factory = DShareFactory(
            address(
                new ERC1967Proxy(
                    address(factoryImpl),
                    abi.encodeCall(
                        DShareFactory.initialize,
                        (address(this), upgrader, address(beacon), address(wrappedBeacon), address(restrictor))
                    )
                )
            )
        );
    }

    function testDeployNewFactory() public {
        DShareFactory factoryImpl = new DShareFactory();

        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(
                DShareFactory.initialize, (address(this), upgrader, address(beacon), address(wrappedBeacon), address(0))
            )
        );

        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(
                DShareFactory.initialize, (address(this), upgrader, address(beacon), address(0), address(restrictor))
            )
        );

        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(
                DShareFactory.initialize,
                (address(this), upgrader, address(0), address(wrappedBeacon), address(restrictor))
            )
        );

        DShareFactory newfactory = DShareFactory(
            address(
                new ERC1967Proxy(
                    address(factoryImpl),
                    abi.encodeCall(
                        DShareFactory.initialize,
                        (address(this), upgrader, address(beacon), address(wrappedBeacon), address(restrictor))
                    )
                )
            )
        );
        assertEq(newfactory.getDShareBeacon(), address(beacon));
        assertEq(newfactory.getWrappedDShareBeacon(), address(wrappedBeacon));
        assertEq(newfactory.getTransferRestrictor(), address(restrictor));

        // create existing listing
        newfactory.createDShare(address(this), "Token", "T", "Wrapped Token", "wT");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, factory.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        newfactory.initializeV2();

        newfactory.initializeV2();
    }

    function testSetNewTransferRestrictor() public {
        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        factory.setNewTransferRestrictor(address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, factory.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        factory.setNewTransferRestrictor(address(restrictor));

        vm.expectEmit(true, true, true, true);
        emit NewTransferRestrictorSet(address(restrictor));
        factory.setNewTransferRestrictor(address(restrictor));
    }

    function testDeployNewDShareViaFactory(string memory name, string memory symbol) public {
        string memory wrappedName = string.concat("Wrapped ", name);
        string memory wrappedSymbol = string.concat(symbol, "w");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, factory.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        factory.createDShare(address(this), name, symbol, wrappedName, wrappedSymbol);

        vm.expectEmit(false, false, false, false);
        emit DShareAdded(address(0), address(0), symbol, name);
        (address newdshare, address newwrappeddshare) =
            factory.createDShare(address(this), name, symbol, wrappedName, wrappedSymbol);
        assertEq(DShare(newdshare).owner(), address(this));
        assertEq(DShare(newdshare).name(), name);
        assertEq(DShare(newdshare).symbol(), symbol);
        assertEq(address(DShare(newdshare).transferRestrictor()), address(restrictor));
        assertEq(WrappedDShare(newwrappeddshare).owner(), address(this));
        assertEq(WrappedDShare(newwrappeddshare).name(), wrappedName);
        assertEq(WrappedDShare(newwrappeddshare).symbol(), wrappedSymbol);
        assertEq(WrappedDShare(newwrappeddshare).asset(), newdshare);
        assertTrue(factory.isTokenDShare(newdshare));
        assertTrue(factory.isTokenWrappedDShare(newwrappeddshare));
        (address[] memory dshares, address[] memory wrappeddshares) = factory.getDShares();
        assertEq(dshares.length, 1);
        assertEq(wrappeddshares.length, 1);
        assertEq(dshares[0], newdshare);
        assertEq(wrappeddshares[0], newwrappeddshare);
    }

    function testAnnounceExistingDShare(string memory name, string memory symbol) public {
        string memory wrappedName = string.concat("Wrapped ", name);
        string memory wrappedSymbol = string.concat(symbol, "w");
        address dshare = address(
            new BeaconProxy(
                address(beacon), abi.encodeCall(DShare.initialize, (address(this), name, symbol, restrictor))
            )
        );
        address wrappedDShare = address(
            new BeaconProxy(
                address(wrappedBeacon),
                abi.encodeCall(WrappedDShare.initialize, (address(this), DShare(dshare), wrappedName, wrappedSymbol))
            )
        );

        vm.expectRevert(DShareFactory.Mismatch.selector);
        factory.announceExistingDShare(address(0), wrappedDShare);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, factory.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        factory.announceExistingDShare(dshare, wrappedDShare);

        vm.expectEmit(true, true, true, true);
        emit DShareAdded(dshare, wrappedDShare, symbol, name);
        factory.announceExistingDShare(dshare, wrappedDShare);
        assertTrue(factory.isTokenDShare(dshare));
        assertTrue(factory.isTokenWrappedDShare(wrappedDShare));
        (address[] memory dshares, address[] memory wrappeddshares) = factory.getDShares();
        assertEq(dshares.length, 1);
        assertEq(wrappeddshares.length, 1);
        assertEq(dshares[0], dshare);
        assertEq(wrappeddshares[0], wrappedDShare);

        vm.expectRevert(DShareFactory.PreviouslyAnnounced.selector);
        factory.announceExistingDShare(dshare, wrappedDShare);
    }
}
