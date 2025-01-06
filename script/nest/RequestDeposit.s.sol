// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../../src/plume-nest/DinariAdapterToken.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract RequestDeposit is Script {
    function run() external {
        uint256 privateKey = vm.envUint("DEPLOY_KEY");
        address user = vm.addr(privateKey);
        DinariAdapterToken adapter = DinariAdapterToken(vm.envAddress("NESTADAPTER"));
        ERC20 usdc = ERC20(vm.envAddress("USDC"));

        console.log("User: %s", user);

        uint256 value = 10_000000;

        vm.startBroadcast(privateKey);

        usdc.approve(address(adapter), value);
        adapter.requestDeposit(value, user, user);

        vm.stopBroadcast();
    }
}
