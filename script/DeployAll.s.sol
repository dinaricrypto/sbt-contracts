// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {IERC20Usdc, IERC20Usdt} from "../src/TokenLockCheck.sol";
import "./DeployAllLib.sol";

contract DeployAll is Script {
    uint64 constant perOrderFee = 1 ether;
    uint24 constant percentageFeeRate = 5_000;
    uint256 constant SELL_GAS_COST = 1000000;
    uint16 constant FORWARDER_FEE = 2000;

    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");

        DeployAllConfig memory cfg = DeployAllConfig({
            deployer: vm.addr(deployerPrivateKey),
            treasury: vm.envAddress("TREASURY"),
            operator: vm.envAddress("OPERATOR"),
            operator2: vm.envAddress("OPERATOR2"),
            distributor: vm.envAddress("DISTRIBUTOR"),
            relayer: vm.envAddress("RELAYER"),
            ethusdoracle: vm.envAddress("ETHUSDORACLE"),
            paymentTokens: new PaymentTokenConfig[](2)
        });
        address usdc = vm.envAddress("USDC");
        address usdt = vm.envAddress("USDT");
        address usdcoracle = vm.envAddress("USDCORACLE");
        address usdtoracle = vm.envAddress("USDTORACLE");

        Fees memory fees = Fees({
            perOrderFee: perOrderFee,
            percentageFeeRate: percentageFeeRate,
            sellGasCost: SELL_GAS_COST,
            forwarderFee: FORWARDER_FEE
        });

        console.log("deployer: %s", cfg.deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        /// ------------------ payment tokens ------------------

        // deploy mock USDC with 6 decimals
        cfg.paymentTokens[0].token = usdc;
        cfg.paymentTokens[0].oracle = usdcoracle;
        cfg.paymentTokens[0].isBlacklistedSelector = IERC20Usdc.isBlacklisted.selector;
        // deploy mock USDT with 6 decimals
        cfg.paymentTokens[1].token = usdt;
        cfg.paymentTokens[1].oracle = usdtoracle;
        cfg.paymentTokens[1].isBlacklistedSelector = IERC20Usdt.isBlackListed.selector;

        /// ------------------ asset tokens ------------------

        DeployAllLib.deployAll(cfg, fees);

        vm.stopBroadcast();
    }
}
