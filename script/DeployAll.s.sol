// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Messager.sol";
import "../src/TransferRestrictor.sol";
import "../src/BridgedTokenFactory.sol";
import "../src/FlatOrderFees.sol";
import {LimitOrderBridge} from "../src/LimitOrderBridge.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployAllScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasuryAddress = vm.envAddress("BRIDGE_TREASURY");
        vm.startBroadcast(deployerPrivateKey);

        new Messager();

        new TransferRestrictor();

        new BridgedTokenFactory();

        IOrderFees orderFees = new FlatOrderFees();

        LimitOrderBridge bridgeImpl = new LimitOrderBridge();
        new ERC1967Proxy(address(bridgeImpl), abi.encodeCall(LimitOrderBridge.initialize, (vm.addr(deployerPrivateKey), treasuryAddress, orderFees)));

        vm.stopBroadcast();
    }
}
