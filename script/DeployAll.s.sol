// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Messager} from "../src/Messager.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {BridgedTokenFactory} from "../src/BridgedTokenFactory.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import {SwapOrderIssuer} from "../src/issuer/SwapOrderIssuer.sol";
import {DirectBuyIssuer} from "../src/issuer/DirectBuyIssuer.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

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
        new TransferRestrictor(deployer);

        // deploy token factory
        new BridgedTokenFactory();

        // deploy fee manager
        IOrderFees orderFees = new OrderFees(deployer, 1 ether, 0.005 ether);

        // deploy SwapOrderIssuer implementation
        SwapOrderIssuer issuerImpl = new SwapOrderIssuer();
        // deploy proxy for SwapOrderIssuer and set implementation
        new ERC1967Proxy(address(issuerImpl), abi.encodeCall(issuerImpl.initialize, (deployer, treasuryAddress, orderFees)));

        // deploy DirectBuyIssuer implementation
        DirectBuyIssuer directIssuerImpl = new DirectBuyIssuer();
        // deploy proxy for DirectBuyIssuer and set implementation
        new ERC1967Proxy(address(directIssuerImpl), abi.encodeCall(directIssuerImpl.initialize, (deployer, treasuryAddress, orderFees)));

        vm.stopBroadcast();
    }
}
