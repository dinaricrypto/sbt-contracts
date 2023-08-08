// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import {BuyOrderIssuer} from "../src/issuer/BuyOrderIssuer.sol";
import {SellOrderProcessor} from "../src/issuer/SellOrderProcessor.sol";
import {DirectBuyIssuer} from "../src/issuer/DirectBuyIssuer.sol";
import {TokenLockCheck, ITokenLockCheck} from "../src/TokenLockCheck.sol";

contract DeployAllScript is Script {
    struct DeployConfig {
        address deployer;
        address owner;
        address treasury;
        address operator;
        address usdc;
        address usdt;
    }

    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        uint256 ownerKey = vm.envUint("OWNER_KEY");
        DeployConfig memory cfg = DeployConfig({
            deployer: vm.addr(deployerPrivateKey),
            owner: vm.addr(ownerKey),
            treasury: vm.envAddress("TREASURY"),
            operator: vm.envAddress("OPERATOR"),
            usdc: vm.envAddress("USDC"),
            usdt: vm.envAddress("USDT")
        });

        console.log("deployer: %s", cfg.deployer);
        console.log("owner: %s", cfg.owner);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        // deploy transfer restrictor
        new TransferRestrictor(cfg.owner);

        // deploy fee manager
        IOrderFees orderFees = new OrderFees(cfg.owner, 1 ether, 0.005 ether);
        TokenLockCheck tokenLockCheck = new TokenLockCheck(cfg.usdc, cfg.usdt);


        // deploy proxy and set implementation
        BuyOrderIssuer buyOrderIssuer = new BuyOrderIssuer(cfg.deployer, cfg.treasury, orderFees, tokenLockCheck);
        // deploy sellOrderProcessor
        SellOrderProcessor sellOrderProcessor = new SellOrderProcessor(cfg.deployer, cfg.treasury, orderFees, tokenLockCheck);
        // deploy proxy and set implementation
        DirectBuyIssuer directBuyIssuer = new DirectBuyIssuer(cfg.deployer, cfg.treasury, orderFees, tokenLockCheck);

        // config operator
        buyOrderIssuer.grantRole(buyOrderIssuer.OPERATOR_ROLE(), cfg.operator);
        sellOrderProcessor.grantRole(sellOrderProcessor.OPERATOR_ROLE(), cfg.operator);
        directBuyIssuer.grantRole(directBuyIssuer.OPERATOR_ROLE(), cfg.operator);

        // config payment token
        buyOrderIssuer.grantRole(buyOrderIssuer.PAYMENTTOKEN_ROLE(), cfg.usdc);
        sellOrderProcessor.grantRole(sellOrderProcessor.PAYMENTTOKEN_ROLE(), cfg.usdc);
        directBuyIssuer.grantRole(directBuyIssuer.PAYMENTTOKEN_ROLE(), cfg.usdc);

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
