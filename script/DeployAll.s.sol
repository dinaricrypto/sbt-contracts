// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {OrderFees, IOrderFees} from "../src/orders/OrderFees.sol";
import {MarketBuyProcessor} from "../src/orders/MarketBuyProcessor.sol";
import {MarketSellProcessor} from "../src/orders/MarketSellProcessor.sol";
import {MarketBuyUnlockedProcessor} from "../src/orders/MarketBuyUnlockedProcessor.sol";
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

        MarketBuyProcessor buyProcessor = new MarketBuyProcessor(cfg.deployer, cfg.treasury, orderFees, tokenLockCheck);

        MarketSellProcessor sellProcessor =
            new MarketSellProcessor(cfg.deployer, cfg.treasury, orderFees, tokenLockCheck);

        MarketBuyUnlockedProcessor directBuyIssuer =
            new MarketBuyUnlockedProcessor(cfg.deployer, cfg.treasury, orderFees, tokenLockCheck);

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
