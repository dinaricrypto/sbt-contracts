// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../test/utils/mocks/MockToken.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract DeployMockPaymentTokenScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // deploy mock USDC with 6 decimals
        uint8 randomValue = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao))) % 250);
        string memory version = Strings.toString(randomValue);
        new MockToken("USD Coin - Dinari", "USDC", version);
        vm.stopBroadcast();
    }
}
