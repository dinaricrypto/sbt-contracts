// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/BridgedERC20.sol";
import "../src/ITransferRestrictor.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployTokenScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address restrictor = vm.envAddress("RESTRICTOR");
        address bridge = vm.envAddress("VAULT_BRIDGE");
        vm.startBroadcast(deployerPrivateKey);

        address deployerAddress = vm.addr(deployerPrivateKey);
        BridgedERC20 token =
        new BridgedERC20(deployerAddress, vm.envString("TOKEN_NAME"), vm.envString("TOKEN_SYMBOL"), "example.com", ITransferRestrictor(restrictor));

        token.grantRoles(bridge, token.minterRole());
        token.grantRoles(deployerAddress, token.minterRole());

        token.mint(deployerAddress, 1 ether);

        vm.stopBroadcast();
    }
}
