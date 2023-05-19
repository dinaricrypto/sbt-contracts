// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Messager.sol";
import "../src/TransferRestrictor.sol";
import "../src/BridgedTokenFactory.sol";
import "../src/FlatOrderFees.sol";
import {SwapOrderIssuer} from "../src/SwapOrderIssuer.sol";
import {DirectBuyIssuer} from "../src/DirectBuyIssuer.sol";
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

        SwapOrderIssuer issuerImpl = new SwapOrderIssuer();
        new ERC1967Proxy(address(issuerImpl), abi.encodeCall(SwapOrderIssuer.initialize, (vm.addr(deployerPrivateKey), treasuryAddress, orderFees)));

        DirectBuyIssuer directIssuerImpl = new DirectBuyIssuer();
        new ERC1967Proxy(address(directIssuerImpl), abi.encodeCall(DirectBuyIssuer.initialize, (vm.addr(deployerPrivateKey), treasuryAddress, orderFees)));

        vm.stopBroadcast();
    }
}
