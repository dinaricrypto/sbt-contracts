// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Messager} from "../src/Messager.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {BridgedTokenFactory} from "../src/BridgedTokenFactory.sol";
import {FlatOrderFees, IOrderFees} from "../src/FlatOrderFees.sol";
import {SwapOrderIssuer} from "../src/SwapOrderIssuer.sol";
import {DirectBuyIssuer} from "../src/DirectBuyIssuer.sol";
import {LimitOrderIssuer} from "../src/LimitOrderIssuer.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployAllScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address treasuryAddress = vm.envAddress("BRIDGE_TREASURY");

        vm.startBroadcast(deployerPrivateKey);

        new Messager();

        new TransferRestrictor();

        new BridgedTokenFactory();

        IOrderFees orderFees = new FlatOrderFees(deployer, 0.005 ether);

        SwapOrderIssuer issuerImpl = new SwapOrderIssuer();
        new ERC1967Proxy(address(issuerImpl), abi.encodeCall(SwapOrderIssuer.initialize, (deployer, treasuryAddress, orderFees)));

        DirectBuyIssuer directIssuerImpl = new DirectBuyIssuer();
        new ERC1967Proxy(address(directIssuerImpl), abi.encodeCall(DirectBuyIssuer.initialize, (deployer, treasuryAddress, orderFees)));

        LimitOrderIssuer limitIssuer = new LimitOrderIssuer();
        new ERC1967Proxy(address(limitIssuer), abi.encodeCall(LimitOrderIssuer.initialize, (deployer, treasuryAddress, orderFees)));

        vm.stopBroadcast();
    }
}
