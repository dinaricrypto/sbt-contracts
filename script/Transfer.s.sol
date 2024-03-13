// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Transfer is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        uint256 senderKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(senderKey);

        IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831).transfer(
            0xAdFeB630a6aaFf7161E200088B02Cf41112f8B98, 123577936
        );

        vm.stopBroadcast();
    }
}
