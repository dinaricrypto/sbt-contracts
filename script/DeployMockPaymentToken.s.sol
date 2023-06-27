// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "solady/test/utils/mocks/MockERC20.sol";

contract DeployMockPaymentTokenScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // deploy mock USDC with 6 decimals
        new MockERC20("Fake USDC", "fkUSDC", 6);

        vm.stopBroadcast();
    }
}
