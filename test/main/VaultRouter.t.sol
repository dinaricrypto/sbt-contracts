// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {Vault, IVault} from "../../src/Vault.sol";
import {VaultRouter} from "../../src/VaultRouter.sol";
import {MockToken} from "../utils/mocks/MockToken.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract VaultRouterTest is Test {
    VaultRouter vaultRouter;
    Vault vault;
    address user;
    address mockAddress;

    function setUp() public {
        vault = new Vault(address(this));
        user = address(2);
        mockAddress = address(3);

        vaultRouter = new VaultRouter(vault);
    }

    function testUpdateVault() public {
        assertEq(address(vaultRouter.vault()), address(vault));

        Vault newVault = new Vault(address(this));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, vaultRouter.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        vaultRouter.updateVaultAddress(newVault);

        vaultRouter.updateVaultAddress(newVault);
        assertEq(address(vaultRouter.vault()), address(newVault));
    }
}
