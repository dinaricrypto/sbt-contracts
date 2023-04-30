// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/TransferRestrictor.sol";
import "../src/Bridge.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasuryAddress = vm.envAddress("BRIDGE_TREASURY");
        vm.startBroadcast(deployerPrivateKey);

        new TransferRestrictor();

        Bridge bridgeImpl = new Bridge();
        new ERC1967Proxy(address(bridgeImpl), abi.encodeCall(Bridge.initialize, (address(this), treasuryAddress)));

        vm.stopBroadcast();
    }
}
