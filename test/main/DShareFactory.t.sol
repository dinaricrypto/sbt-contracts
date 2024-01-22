// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DShareFactory} from "../../src/DShareFactory.sol";
import {TransferRestrictor} from "../../src/TransferRestrictor.sol";
import {DShare} from "../../src/DShare.sol";
import {WrappedDShare} from "../../src/WrappedDShare.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DShareFactoryTest is Test {
    DShareFactory factory;
    TransferRestrictor restrictor;
    UpgradeableBeacon beacon;
    UpgradeableBeacon wrappedBeacon;

    event DShareCreated(address indexed dShare, address indexed wrappedDShare, string indexed symbol, string name);
    event NewTransferRestrictorSet(address indexed transferRestrictor);

    function setUp() public {
        restrictor = new TransferRestrictor(address(this));
        DShare tokenImplementation = new DShare();
        beacon = new UpgradeableBeacon(address(tokenImplementation), address(this));
        WrappedDShare wrappedTokenImplementation = new WrappedDShare();
        wrappedBeacon = new UpgradeableBeacon(address(wrappedTokenImplementation), address(this));

        DShareFactory factoryImpl = new DShareFactory();
        factory = DShareFactory(
            address(
                new ERC1967Proxy(
                    address(factoryImpl),
                    abi.encodeCall(DShareFactory.initialize, (address(this), beacon, wrappedBeacon, restrictor))
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
                DShareFactory.initialize, (address(this), beacon, wrappedBeacon, TransferRestrictor(address(0)))
            )
        );

        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(DShareFactory.initialize, (address(this), beacon, UpgradeableBeacon(address(0)), restrictor))
        );

        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(
                DShareFactory.initialize, (address(this), UpgradeableBeacon(address(0)), wrappedBeacon, restrictor)
            )
        );

        new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(DShareFactory.initialize, (address(this), beacon, wrappedBeacon, restrictor))
        );
    }

    function testSetNewTransferRestrictor() public {
        vm.expectRevert(DShareFactory.ZeroAddress.selector);
        factory.setNewTransferRestrictor(TransferRestrictor(address(0)));

        vm.expectEmit(true, true, true, true);
        emit NewTransferRestrictorSet(address(restrictor));
        factory.setNewTransferRestrictor(restrictor);
    }

    function testDeployNewDShareViaFactory(string memory name, string memory symbol) public {
        string memory wrappedName = string.concat("Wrapped ", name);
        string memory wrappedSymbol = string.concat(symbol, "w");
        vm.expectEmit(false, false, false, false);
        emit DShareCreated(address(0), address(0), symbol, name);
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
    }
}
