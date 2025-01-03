// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../../src/plume-nest/DinariAdapterToken.sol";

contract FinalizeDeposit is Script {
    function run() external {
        uint256 privateKey = vm.envUint("DEPLOY_KEY");
        address user = vm.addr(privateKey);
        DinariAdapterToken adapter = DinariAdapterToken(vm.envAddress("NESTADAPTER"));
        // This would be the Nest contract
        address controller = user;

        console.log("User: %s", user);

        uint256 depositId = 0;

        vm.startBroadcast(privateKey);

        uint256 claimableDeposit = adapter.claimableDepositRequest(depositId, controller);
        adapter.deposit(claimableDeposit, user, controller);

        vm.stopBroadcast();
    }
}
