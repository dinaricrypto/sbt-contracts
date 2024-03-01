// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {DShare} from "../src/DShare.sol";
import {WrappedDShare} from "../src/WrappedDShare.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {TokenLockCheck, ITokenLockCheck, IERC20Usdc} from "../src/TokenLockCheck.sol";
import {ForwarderPyth} from "../src/forwarder/ForwarderPyth.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DShareFactory} from "../src/DShareFactory.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {Vault} from "../src/orders/Vault.sol";
import {FulfillmentRouter} from "../src/orders/FulfillmentRouter.sol";
import {MockToken} from "../test/utils/mocks/MockToken.sol";

contract DeployAll is Script {
    struct DeployConfig {
        address deployer;
        address treasury;
        address operator;
        address operator2;
        address relayer;
        address distributor;
        address usdb;
        address pyth;
        bytes32 ethusdoracleid;
    }

    struct Deployments {
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
        ForwarderPyth forwarder;
        FulfillmentRouter fulfillmentRouter;
        Vault vault;
        DividendDistribution dividendDistributor;
    }

    uint256 constant SELL_GAS_COST = 421_549;

    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        DeployConfig memory cfg = DeployConfig({
            deployer: vm.addr(deployerPrivateKey),
            treasury: vm.envAddress("TREASURY"),
            operator: vm.envAddress("OPERATOR"),
            operator2: vm.envAddress("OPERATOR2"),
            relayer: vm.envAddress("RELAYER"),
            distributor: vm.envAddress("DISTRIBUTOR"),
            usdb: vm.envAddress("USDB"),
            pyth: vm.envAddress("PYTH"),
            ethusdoracleid: vm.envBytes32("ETHUSDORACLEID")
        });

        Deployments memory deps;

        console.log("deployer: %s", cfg.deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        /// ------------------ asset tokens ------------------

        // deploy transfer restrictor
        deps.transferRestrictor = new TransferRestrictor(cfg.deployer);

        // deploy dShares logic implementation
        deps.dShareImplementation = address(new DShare());

        // deploy dShares beacon
        deps.dShareBeacon = new UpgradeableBeacon(deps.dShareImplementation, cfg.deployer);

        // deploy wrapped dShares logic implementation
        deps.wrappeddShareImplementation = address(new WrappedDShare());

        // deploy wrapped dShares beacon
        deps.wrappeddShareBeacon = new UpgradeableBeacon(deps.wrappeddShareImplementation, cfg.deployer);

        // deploy dShare factory
        deps.dShareFactoryImplementation = address(new DShareFactory());

        new ERC1967Proxy(
            deps.dShareFactoryImplementation,
            abi.encodeCall(
                DShareFactory.initialize,
                (
                    cfg.deployer,
                    address(deps.dShareBeacon),
                    address(deps.wrappeddShareBeacon),
                    address(deps.transferRestrictor)
                )
            )
        );

        /// ------------------ order processors ------------------

        // deploy blacklist prechecker
        deps.tokenLockCheck = new TokenLockCheck();

        deps.orderProcessorImplementation = new OrderProcessor();
        deps.orderProcessor = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(deps.orderProcessorImplementation),
                    abi.encodeCall(OrderProcessor.initialize, (cfg.deployer, cfg.treasury, deps.tokenLockCheck))
                )
            )
        );

        deps.directBuyIssuerImplementation = new BuyUnlockedProcessor();
        deps.directBuyIssuer = BuyUnlockedProcessor(
            address(
                new ERC1967Proxy(
                    address(deps.directBuyIssuerImplementation),
                    abi.encodeCall(OrderProcessor.initialize, (cfg.deployer, cfg.treasury, deps.tokenLockCheck))
                )
            )
        );

        // config payment token
        OrderProcessor.FeeRates memory defaultFees = OrderProcessor.FeeRates({
            perOrderFeeBuy: 1 ether,
            percentageFeeRateBuy: 0,
            perOrderFeeSell: 1 ether,
            percentageFeeRateSell: 5_000
        });

        deps.orderProcessor.setDefaultFees(cfg.usdb, defaultFees);
        deps.directBuyIssuer.setDefaultFees(cfg.usdb, defaultFees);

        /// ------------------ forwarder ------------------

        deps.forwarder = new ForwarderPyth(cfg.pyth, cfg.ethusdoracleid, SELL_GAS_COST);

        deps.forwarder.setPaymentOracle(cfg.usdb, bytes32(uint256(1)));

        deps.forwarder.setSupportedModule(address(deps.orderProcessor), true);
        deps.forwarder.setSupportedModule(address(deps.directBuyIssuer), true);

        deps.forwarder.setRelayer(cfg.relayer, true);

        deps.orderProcessor.grantRole(deps.orderProcessor.FORWARDER_ROLE(), address(deps.forwarder));
        deps.directBuyIssuer.grantRole(deps.directBuyIssuer.FORWARDER_ROLE(), address(deps.forwarder));

        /// ------------------ vault ------------------

        deps.fulfillmentRouter = new FulfillmentRouter(cfg.deployer);
        deps.orderProcessor.grantRole(deps.orderProcessor.OPERATOR_ROLE(), address(deps.fulfillmentRouter));
        deps.directBuyIssuer.grantRole(deps.directBuyIssuer.OPERATOR_ROLE(), address(deps.fulfillmentRouter));
        deps.fulfillmentRouter.grantRole(deps.fulfillmentRouter.OPERATOR_ROLE(), cfg.operator);
        deps.fulfillmentRouter.grantRole(deps.fulfillmentRouter.OPERATOR_ROLE(), cfg.operator2);

        deps.vault = new Vault(cfg.deployer);
        deps.vault.grantRole(deps.vault.OPERATOR_ROLE(), address(deps.fulfillmentRouter));

        /// ------------------ dividend distributor ------------------

        deps.dividendDistributor = new DividendDistribution(cfg.deployer);

        // add dividend operator
        deps.dividendDistributor.grantRole(deps.dividendDistributor.DISTRIBUTOR_ROLE(), cfg.distributor);

        vm.stopBroadcast();
    }
}
