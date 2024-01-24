// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {MockToken} from "../test/utils/mocks/MockToken.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {DShare} from "../src/DShare.sol";
import {WrappedDShare} from "../src/WrappedDShare.sol";
import {TokenLockCheck} from "../src/TokenLockCheck.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {Forwarder} from "../src/forwarder/Forwarder.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";
import {DShareFactory} from "../src/DShareFactory.sol";
import {MockChainlinkOracle} from "../test/utils/mocks/MockChainlinkOracle.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployAllSandbox is Script {
    struct DeployConfig {
        address deployer;
        address treasury;
        address operator;
        address distributor;
        address relayer;
        address ethusdoracle;
        address usdcoracle;
    }

    struct Deployments {
        MockToken usdc;
        MockToken usdt;
        MockToken usdce;
        TransferRestrictor transferRestrictor;
        address dShareImplementation;
        UpgradeableBeacon dShareBeacon;
        address wrappeddShareImplementation;
        UpgradeableBeacon wrappeddShareBeacon;
        address dShareFactoryImplementation;
        DShareFactory dShareFactory;
        TokenLockCheck tokenLockCheck;
        OrderProcessor orderProcessorImplementation;
        OrderProcessor orderProcessor;
        BuyUnlockedProcessor directBuyIssuerImplementation;
        BuyUnlockedProcessor directBuyIssuer;
        Forwarder forwarder;
        DividendDistribution dividendDistributor;
    }

    uint64 constant perOrderFee = 1 ether;
    uint24 constant percentageFeeRate = 5_000;
    uint256 constant SELL_GAS_COST = 1000000;

    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");

        DeployConfig memory cfg = DeployConfig({
            deployer: vm.addr(deployerPrivateKey),
            treasury: vm.envAddress("TREASURY"),
            operator: vm.envAddress("OPERATOR"),
            distributor: vm.envAddress("DISTRIBUTOR"),
            relayer: vm.envAddress("RELAYER"),
            // ethusdoracle: vm.envAddress("ETHUSDORACLE"),
            // usdcoracle: vm.envAddress("USDCORACLE")
            ethusdoracle: address(new MockChainlinkOracle("ETH/USD", 2239_80000000)),
            usdcoracle: address(new MockChainlinkOracle("USDC/USD", 1_00000000))
        });

        Deployments memory deployments;

        console.log("deployer: %s", cfg.deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        /// ------------------ payment tokens ------------------

        // deploy mock USDC with 6 decimals
        deployments.usdc = new MockToken("USD Coin - Dinari", "USDC");
        // deploy mock USDT with 6 decimals
        deployments.usdt = new MockToken("Tether USD - Dinari", "USDT");
        // deploy mock USDC.e with 6 decimals
        deployments.usdce = new MockToken("USD Coin - Dinari", "USDC.e");

        /// ------------------ asset tokens ------------------

        // deploy transfer restrictor
        deployments.transferRestrictor = new TransferRestrictor(cfg.deployer);

        // deploy dShares logic implementation
        deployments.dShareImplementation = address(new DShare());

        // deploy dShares beacon
        deployments.dShareBeacon = new UpgradeableBeacon(deployments.dShareImplementation, cfg.deployer);

        // deploy wrapped dShares logic implementation
        deployments.wrappeddShareImplementation = address(new WrappedDShare());

        // deploy wrapped dShares beacon
        deployments.wrappeddShareBeacon = new UpgradeableBeacon(deployments.wrappeddShareImplementation, cfg.deployer);

        // deploy dShare factory
        deployments.dShareFactoryImplementation = address(new DShareFactory());

        deployments.dShareFactory = DShareFactory(
            address(
                new ERC1967Proxy(
                    deployments.dShareFactoryImplementation,
                    abi.encodeCall(
                        DShareFactory.initialize,
                        (
                            cfg.deployer,
                            address(deployments.dShareBeacon),
                            address(deployments.wrappeddShareBeacon),
                            address(deployments.transferRestrictor)
                        )
                    )
                )
            )
        );

        /// ------------------ order processors ------------------

        // deploy blacklist prechecker
        deployments.tokenLockCheck = new TokenLockCheck(address(0), address(0));
        // add USDC
        deployments.tokenLockCheck.setCallSelector(address(deployments.usdc), deployments.usdc.isBlacklisted.selector);
        // add USDT.e
        deployments.tokenLockCheck.setCallSelector(address(deployments.usdt), deployments.usdt.isBlocked.selector);
        // add USDC.e
        deployments.tokenLockCheck.setCallSelector(address(deployments.usdce), deployments.usdce.isBlacklisted.selector);

        deployments.orderProcessorImplementation = new OrderProcessor();
        deployments.orderProcessor = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(deployments.orderProcessorImplementation),
                    abi.encodeCall(OrderProcessor.initialize, (cfg.deployer, cfg.treasury, deployments.tokenLockCheck))
                )
            )
        );

        deployments.directBuyIssuerImplementation = new BuyUnlockedProcessor();
        deployments.directBuyIssuer = BuyUnlockedProcessor(
            address(
                new ERC1967Proxy(
                    address(deployments.directBuyIssuerImplementation),
                    abi.encodeCall(OrderProcessor.initialize, (cfg.deployer, cfg.treasury, deployments.tokenLockCheck))
                )
            )
        );

        // config operator
        deployments.orderProcessor.grantRole(deployments.orderProcessor.OPERATOR_ROLE(), cfg.operator);
        deployments.directBuyIssuer.grantRole(deployments.directBuyIssuer.OPERATOR_ROLE(), cfg.operator);

        // config payment token
        OrderProcessor.FeeRates memory defaultFees = OrderProcessor.FeeRates({
            perOrderFeeBuy: perOrderFee,
            percentageFeeRateBuy: percentageFeeRate,
            perOrderFeeSell: perOrderFee,
            percentageFeeRateSell: percentageFeeRate
        });

        deployments.orderProcessor.setDefaultFees(address(deployments.usdc), defaultFees);
        deployments.directBuyIssuer.setDefaultFees(address(deployments.usdc), defaultFees);

        deployments.orderProcessor.setDefaultFees(address(deployments.usdt), defaultFees);
        deployments.directBuyIssuer.setDefaultFees(address(deployments.usdt), defaultFees);

        deployments.orderProcessor.setDefaultFees(address(deployments.usdce), defaultFees);
        deployments.directBuyIssuer.setDefaultFees(address(deployments.usdce), defaultFees);

        /// ------------------ forwarder ------------------

        deployments.forwarder = new Forwarder(cfg.ethusdoracle, SELL_GAS_COST);
        deployments.forwarder.setFeeBps(2000);

        deployments.forwarder.setPaymentOracle(address(deployments.usdc), cfg.usdcoracle);
        deployments.forwarder.setPaymentOracle(address(deployments.usdce), cfg.usdcoracle);
        deployments.forwarder.setPaymentOracle(address(deployments.usdt), cfg.usdcoracle);

        deployments.forwarder.setSupportedModule(address(deployments.orderProcessor), true);
        deployments.forwarder.setSupportedModule(address(deployments.directBuyIssuer), true);

        deployments.forwarder.setRelayer(cfg.relayer, true);

        deployments.orderProcessor.grantRole(
            deployments.orderProcessor.FORWARDER_ROLE(), address(deployments.forwarder)
        );
        deployments.directBuyIssuer.grantRole(
            deployments.directBuyIssuer.FORWARDER_ROLE(), address(deployments.forwarder)
        );

        /// ------------------ dividend distributor ------------------

        deployments.dividendDistributor = new DividendDistribution(cfg.deployer);

        // add distributor
        deployments.dividendDistributor.grantRole(deployments.dividendDistributor.DISTRIBUTOR_ROLE(), cfg.distributor);

        vm.stopBroadcast();
    }
}
