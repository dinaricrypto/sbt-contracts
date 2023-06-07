// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import {BuyOrderIssuer} from "../src/issuer/BuyOrderIssuer.sol";
import {SellOrderProcessor} from "../src/issuer/SellOrderProcessor.sol";
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

        // deploy transfer restrictor
        new TransferRestrictor(deployer);

        // deploy fee manager
        IOrderFees orderFees = new OrderFees(deployer, 1 ether, 0.005 ether);

        // deploy implementation
        BuyOrderIssuer buyImpl = new BuyOrderIssuer();
        // deploy proxy and set implementation
        new ERC1967Proxy(address(buyImpl), abi.encodeCall(buyImpl.initialize, (deployer, treasuryAddress, orderFees)));

        // deploy implementation
        SellOrderProcessor sellImpl = new SellOrderProcessor();
        // deploy proxy and set implementation
        new ERC1967Proxy(address(sellImpl), abi.encodeCall(sellImpl.initialize, (deployer, treasuryAddress, orderFees)));

        // deploy implementation
        DirectBuyIssuer directIssuerImpl = new DirectBuyIssuer();
        // deploy proxy and set implementation
        new ERC1967Proxy(address(directIssuerImpl), abi.encodeCall(directIssuerImpl.initialize, (deployer, treasuryAddress, orderFees)));

        vm.stopBroadcast();
    }
}
