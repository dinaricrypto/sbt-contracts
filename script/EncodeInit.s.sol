// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/DShareFactory.sol";

contract Encode is Script {
    function run() external {
        bytes memory data = abi.encodeCall(DShareFactory.initializeV2, ());
        console.log("Encoded call:");
        console.logBytes(data);
    }
}
