// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

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
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        uint256 ownerKey = vm.envUint("OWNER_KEY");
        address owner = vm.addr(ownerKey);
        address treasury = vm.envAddress("TREASURY");
        address operator = vm.envAddress("OPERATOR");
        address usdc = vm.envAddress("USDC");

        console.log("deployer: %s", deployer);
        console.log("owner: %s", owner);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        // deploy transfer restrictor
        new TransferRestrictor(owner);

        // deploy fee manager
        IOrderFees orderFees = new OrderFees(owner, 1 ether, 0.005 ether);

        // deploy implementation
        BuyOrderIssuer buyImpl = new BuyOrderIssuer();
        // deploy proxy and set implementation
        BuyOrderIssuer buyOrderIssuer = BuyOrderIssuer(
            address(
                new ERC1967Proxy(address(buyImpl), abi.encodeCall(buyImpl.initialize, (deployer, treasury, orderFees)))
            )
        );

        // deploy implementation
        SellOrderProcessor sellImpl = new SellOrderProcessor();
        // deploy proxy and set implementation
        SellOrderProcessor sellOrderProcessor = SellOrderProcessor(
            address(
                new ERC1967Proxy(address(sellImpl), abi.encodeCall(sellImpl.initialize, (deployer, treasury, orderFees)))
            )
        );

        // deploy implementation
        DirectBuyIssuer directIssuerImpl = new DirectBuyIssuer();
        // deploy proxy and set implementation
        DirectBuyIssuer directBuyIssuer = DirectBuyIssuer(
            address(
                new ERC1967Proxy(address(directIssuerImpl), abi.encodeCall(directIssuerImpl.initialize, (deployer, treasury, orderFees)))
            )
        );

        // config operator
        buyOrderIssuer.grantRole(buyOrderIssuer.OPERATOR_ROLE(), operator);
        sellOrderProcessor.grantRole(sellOrderProcessor.OPERATOR_ROLE(), operator);
        directBuyIssuer.grantRole(directBuyIssuer.OPERATOR_ROLE(), operator);

        // config payment token
        buyOrderIssuer.grantRole(buyOrderIssuer.PAYMENTTOKEN_ROLE(), usdc);
        sellOrderProcessor.grantRole(sellOrderProcessor.PAYMENTTOKEN_ROLE(), usdc);
        directBuyIssuer.grantRole(directBuyIssuer.PAYMENTTOKEN_ROLE(), usdc);

        // transfer ownership
        // buyOrderIssuer.beginDefaultAdminTransfer(owner);
        // sellOrderProcessor.beginDefaultAdminTransfer(owner);
        // directBuyIssuer.beginDefaultAdminTransfer(owner);

        vm.stopBroadcast();

        // // accept ownership transfer
        // vm.startBroadcast(owner);

        // buyOrderIssuer.acceptDefaultAdminTransfer();
        // sellOrderProcessor.acceptDefaultAdminTransfer();
        // directBuyIssuer.acceptDefaultAdminTransfer();

        // vm.stopBroadcast();
    }
}
