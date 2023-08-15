// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {OrderFees, IOrderFees} from "../src/orders/OrderFees.sol";
import {BuyProcessor} from "../src/orders/BuyProcessor.sol";
import {SellProcessor} from "../src/orders/SellProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
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
        IOrderFees orderFees = new OrderFees(cfg.owner, 1_000_000, 5_000);
        TokenLockCheck tokenLockCheck = new TokenLockCheck(cfg.usdc, cfg.usdt);

        BuyProcessor buyProcessor = new BuyProcessor(cfg.deployer, cfg.treasury, orderFees, tokenLockCheck);

        SellProcessor sellProcessor = new SellProcessor(cfg.deployer, cfg.treasury, orderFees, tokenLockCheck);

        BuyUnlockedProcessor directBuyIssuer =
            new BuyUnlockedProcessor(cfg.deployer, cfg.treasury, orderFees, tokenLockCheck);

        // config operator
        buyProcessor.grantRole(buyProcessor.OPERATOR_ROLE(), cfg.operator);
        sellProcessor.grantRole(sellProcessor.OPERATOR_ROLE(), cfg.operator);
        directBuyIssuer.grantRole(directBuyIssuer.OPERATOR_ROLE(), cfg.operator);

        // config payment token
        buyProcessor.grantRole(buyProcessor.PAYMENTTOKEN_ROLE(), cfg.usdc);
        sellProcessor.grantRole(sellProcessor.PAYMENTTOKEN_ROLE(), cfg.usdc);
        directBuyIssuer.grantRole(directBuyIssuer.PAYMENTTOKEN_ROLE(), cfg.usdc);

        // transfer ownership
        // buyProcessor.beginDefaultAdminTransfer(owner);
        // sellProcessor.beginDefaultAdminTransfer(owner);
        // directBuyIssuer.beginDefaultAdminTransfer(owner);

        vm.stopBroadcast();

        // // accept ownership transfer
        // vm.startBroadcast(owner);

        // buyProcessor.acceptDefaultAdminTransfer();
        // sellProcessor.acceptDefaultAdminTransfer();
        // directBuyIssuer.acceptDefaultAdminTransfer();

        // vm.stopBroadcast();
    }
}
