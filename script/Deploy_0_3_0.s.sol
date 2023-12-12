// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {TokenLockCheck, ITokenLockCheck, IERC20Usdc} from "../src/TokenLockCheck.sol";
import {Forwarder} from "../src/forwarder/Forwarder.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployScript is Script {
    // TODO: vault, fulfillment router
    struct DeployConfig {
        address deployer;
        ITokenLockCheck tokenLockCheck;
        address treasury;
        address operator;
        address operator2;
        address usdc;
        address usdcOracle;
        address ethUsdOracle;
        address relayer;
    }

    uint64 constant perOrderFee = 1 ether;
    uint24 constant percentageFeeRate = 5_000;
    uint256 constant SELL_GAS_COST = 421502;
    uint256 constant CANCEL_GAS_COST = 64523;
    uint16 constant FORWARDER_FEE_BPS = 2000;

    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        DeployConfig memory cfg = DeployConfig({
            deployer: vm.addr(deployerPrivateKey),
            tokenLockCheck: TokenLockCheck(vm.envAddress("TOKENLOCKCHECK")),
            treasury: vm.envAddress("TREASURY"),
            operator: vm.envAddress("OPERATOR"),
            operator2: vm.envAddress("OPERATOR2"),
            usdc: vm.envAddress("USDC"),
            usdcOracle: vm.envAddress("USDCORACLE"),
            ethUsdOracle: vm.envAddress("ETHUSDORACLE"),
            relayer: vm.envAddress("RELAYER")
        });

        console.log("deployer: %s", cfg.deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        /// ------------------ order processors ------------------

        OrderProcessor orderProcessorImpl = new OrderProcessor();
        OrderProcessor orderProcessor = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(orderProcessorImpl),
                    abi.encodeCall(
                        OrderProcessor.initialize,
                        (
                            cfg.deployer,
                            cfg.treasury,
                            OrderProcessor.FeeRates({
                                perOrderFeeBuy: perOrderFee,
                                percentageFeeRateBuy: percentageFeeRate,
                                perOrderFeeSell: perOrderFee,
                                percentageFeeRateSell: percentageFeeRate
                            }),
                            cfg.tokenLockCheck
                        )
                    )
                )
            )
        );

        BuyUnlockedProcessor directBuyIssuerImpl = new BuyUnlockedProcessor();
        BuyUnlockedProcessor directBuyIssuer = BuyUnlockedProcessor(
            address(
                new ERC1967Proxy(
                    address(directBuyIssuerImpl),
                    abi.encodeCall(
                        OrderProcessor.initialize,
                        (
                            cfg.deployer,
                            cfg.treasury,
                            OrderProcessor.FeeRates({
                                perOrderFeeBuy: perOrderFee,
                                percentageFeeRateBuy: percentageFeeRate,
                                perOrderFeeSell: perOrderFee,
                                percentageFeeRateSell: percentageFeeRate
                            }),
                            cfg.tokenLockCheck
                        )
                    )
                )
            )
        );

        // config operator
        orderProcessor.grantRole(orderProcessor.OPERATOR_ROLE(), cfg.operator);
        directBuyIssuer.grantRole(directBuyIssuer.OPERATOR_ROLE(), cfg.operator);
        orderProcessor.grantRole(orderProcessor.OPERATOR_ROLE(), cfg.operator2);
        directBuyIssuer.grantRole(directBuyIssuer.OPERATOR_ROLE(), cfg.operator2);

        // config payment token
        orderProcessor.grantRole(orderProcessor.PAYMENTTOKEN_ROLE(), cfg.usdc);
        directBuyIssuer.grantRole(directBuyIssuer.PAYMENTTOKEN_ROLE(), cfg.usdc);

        /// ------------------ forwarder ------------------

        Forwarder forwarder = new Forwarder(cfg.ethUsdOracle, SELL_GAS_COST);
        forwarder.setCancellationGasCost(CANCEL_GAS_COST);
        forwarder.setFeeBps(FORWARDER_FEE_BPS);

        forwarder.setPaymentOracle(address(cfg.usdc), cfg.usdcOracle);

        forwarder.setSupportedModule(address(orderProcessor), true);
        forwarder.setSupportedModule(address(directBuyIssuer), true);

        forwarder.setRelayer(cfg.relayer, true);

        orderProcessor.grantRole(orderProcessor.FORWARDER_ROLE(), address(forwarder));
        directBuyIssuer.grantRole(directBuyIssuer.FORWARDER_ROLE(), address(forwarder));

        vm.stopBroadcast();
    }
}
