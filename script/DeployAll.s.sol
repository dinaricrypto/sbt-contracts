// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Messager.sol";
import "../src/TransferRestrictor.sol";
import "../src/BridgedTokenFactory.sol";
import "../src/FlatOrderFees.sol";
import {SwapOrderIssuer} from "../src/SwapOrderIssuer.sol";
import {DirectBuyIssuer} from "../src/DirectBuyIssuer.sol";
import {LimitOrderIssuer} from "../src/LimitOrderIssuer.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployAllScript is Script {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address treasuryAddress = vm.envAddress("BRIDGE_TREASURY");

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        // deploy messager
        new Messager();

        // deploy transfer restrictor
        new TransferRestrictor();

        // deploy token factory
        new BridgedTokenFactory();

        // deploy fee manager
        IOrderFees orderFees = new FlatOrderFees(deployer, 0.005 ether);

        // deploy SwapOrderIssuer implementation
        SwapOrderIssuer issuerImpl = new SwapOrderIssuer();
        // deploy proxy for SwapOrderIssuer and set implementation
        new ERC1967Proxy(address(issuerImpl), abi.encodeCall(SwapOrderIssuer.initialize, (deployer, treasuryAddress, orderFees)));

        // deploy DirectBuyIssuer implementation
        DirectBuyIssuer directIssuerImpl = new DirectBuyIssuer();
        // deploy proxy for DirectBuyIssuer and set implementation
        new ERC1967Proxy(address(directIssuerImpl), abi.encodeCall(DirectBuyIssuer.initialize, (deployer, treasuryAddress, orderFees)));

        // deploy LimitOrderIssuer implementation
        LimitOrderIssuer limitIssuer = new LimitOrderIssuer();
        // deploy proxy for LimitOrderIssuer and set implementation
        new ERC1967Proxy(address(limitIssuer), abi.encodeCall(LimitOrderIssuer.initialize, (deployer, treasuryAddress, orderFees)));

        vm.stopBroadcast();
    }
}
