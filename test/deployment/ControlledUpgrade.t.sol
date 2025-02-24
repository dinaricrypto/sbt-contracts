// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockControlled, ControlledUpgradeable} from "../utils/mocks/MockControlled.sol";
import {MockControlledV2} from "../utils/mocks/MockControlledV2.sol";
import {MockOwnableUpgradeable} from "../utils/mocks/MockOwnable.sol";
import {MockOwnableControlled} from "../utils/mocks/MockOwnableControlled.sol";
import {MockUpgradeableContract} from "../utils/mocks/MockAccessControl.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract ControlledUpgradeableTest is Test {
    MockControlled controlled;
    MockOwnableUpgradeable ownable;
    MockOwnableControlled ownableControlled;
    MockUpgradeableContract upgradeableContract;
    MockControlledV2 controlledV2;

    // constant
    address public constant ADMIN = address(0x1234);
    address public constant UPGRADER = address(0x1235);

    function setUp() public {
        MockOwnableUpgradeable ownableImpl = new MockOwnableUpgradeable();
        MockUpgradeableContract upgradeableContractImpl = new MockUpgradeableContract();

        upgradeableContract = MockUpgradeableContract(
            address(
                new ERC1967Proxy(
                    address(upgradeableContractImpl),
                    abi.encodeWithSelector(upgradeableContractImpl.initialize.selector, ADMIN)
                )
            )
        );

        ownable = MockOwnableUpgradeable(
            address(
                new ERC1967Proxy(address(ownableImpl), abi.encodeWithSelector(ownableImpl.initialize.selector, ADMIN))
            )
        );
    }

    function test_upgrade_access_control() public {
        MockControlled controlledImpl = new MockControlled();

        vm.prank(ADMIN);
        upgradeableContract.upgradeToAndCall(
            address(controlledImpl), abi.encodeWithSelector(MockControlled.reinitialize.selector, UPGRADER)
        );

        //check if the upgrade is successful
        assertEq(upgradeableContract.hasRole(controlledImpl.UPGRADER_ROLE(), UPGRADER), true);
        assertEq(upgradeableContract.hasRole(upgradeableContract.DEFAULT_ADMIN_ROLE(), ADMIN), true);
        assertEq(MockControlled(address(upgradeableContract)).version(), 2);

        //upgrade with upgrader
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ADMIN, controlledImpl.UPGRADER_ROLE()
            )
        );
        vm.prank(ADMIN);
        upgradeableContract.upgradeToAndCall(
            address(controlledImpl), abi.encodeWithSelector(MockControlled.reinitialize.selector, UPGRADER)
        );

        MockControlledV2 controlledV2Impl = new MockControlledV2();

        vm.startPrank(UPGRADER);
        upgradeableContract.upgradeToAndCall(
            address(controlledV2Impl), abi.encodeWithSelector(MockControlledV2.reinitialize.selector, 0)
        );
        assertEq(MockControlled(address(upgradeableContract)).version(), 3);
        assertEq(MockControlled(address(upgradeableContract)).publicVersion(), "1.0.2");
        vm.stopPrank();
    }

    function test_ugprade_ownable() public {
        assertEq(ownable.owner(), ADMIN);
        MockOwnableControlled ownableControlledImpl = new MockOwnableControlled();

        vm.prank(ADMIN);
        ownable.upgradeToAndCall(
            address(ownableControlledImpl),
            abi.encodeWithSelector(MockOwnableControlled.reinitialize.selector, ADMIN, UPGRADER)
        );
        assertEq(
            MockOwnableControlled(address(ownable)).hasRole(ownableControlledImpl.DEFAULT_ADMIN_ROLE(), ADMIN), true
        );
        assertEq(MockOwnableControlled(address(ownable)).hasRole(ownableControlledImpl.UPGRADER_ROLE(), UPGRADER), true);
        assertEq(MockOwnableControlled(address(ownable)).version(), 2);
        assertEq(MockOwnableControlled(address(ownable)).publicVersion(), "1.0.1");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ADMIN, ownableControlledImpl.UPGRADER_ROLE()
            )
        );
        vm.prank(ADMIN);
        ownable.upgradeToAndCall(
            address(ownableControlledImpl),
            abi.encodeWithSelector(MockOwnableControlled.reinitialize.selector, ADMIN, UPGRADER)
        );
    }
}
