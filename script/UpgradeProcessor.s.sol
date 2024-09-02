// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";

contract UpgradeProcessor is Script {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        OrderProcessor processor = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));

        console.log("deployer: %s", deployer);

        bytes32 salt = keccak256(abi.encodePacked("0.4.2"));

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        /// ------------------ order processor ------------------

        // In case of multiple deployments on single chain, check if the contract is already deployed
        // address implAddress = getAddress(deployer, keccak256(type(OrderProcessor).creationCode), salt);
        // if (implAddress.code.length == 0) {
        OrderProcessor orderProcessorImplementation = new OrderProcessor{salt: salt}();
        // assert(address(orderProcessorImplementation) == implAddress);
        // }
        console.log("order processor implementation: %s", address(orderProcessorImplementation));
        processor.upgradeToAndCall(address(orderProcessorImplementation), "");

        vm.stopBroadcast();
    }

    function getAddress(address sender, bytes32 creationCodeHash, bytes32 salt) public pure returns (address addr) {
        assembly {
            let ptr := mload(0x40)

            mstore(add(ptr, 0x40), creationCodeHash)
            mstore(add(ptr, 0x20), salt)
            mstore(ptr, sender)
            let start := add(ptr, 0x0b)
            mstore8(start, 0xff)
            addr := keccak256(start, 85)
        }
    }
}
