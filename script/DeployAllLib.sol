// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {DShare} from "../src/DShare.sol";
import {WrappedDShare} from "../src/WrappedDShare.sol";
import {Vault} from "../src/orders/Vault.sol";
import {FulfillmentRouter} from "../src/orders/FulfillmentRouter.sol";
import {TokenLockCheck} from "../src/TokenLockCheck.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {Forwarder} from "../src/forwarder/Forwarder_v030.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";
import {DShareFactory} from "../src/DShareFactory.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

struct PaymentTokenConfig {
    address token;
    address oracle;
    bytes4 isBlacklistedSelector;
}

struct DeployAllConfig {
    address deployer;
    address treasury;
    address operator;
    address operator2;
    address distributor;
    address relayer;
    address ethusdoracle;
    PaymentTokenConfig[] paymentTokens;
}

struct Fees {
    uint64 perOrderFee;
    uint24 percentageFeeRate;
    uint256 sellGasCost;
    uint16 forwarderFee;
}

struct Deployments {
    TransferRestrictor transferRestrictor;
    address dShareImplementation;
    UpgradeableBeacon dShareBeacon;
    address wrappeddShareImplementation;
    UpgradeableBeacon wrappeddShareBeacon;
    address dShareFactoryImplementation;
    DShareFactory dShareFactory;
    Vault vault;
    FulfillmentRouter fulfillmentRouter;
    TokenLockCheck tokenLockCheck;
    OrderProcessor orderProcessorImplementation;
    OrderProcessor orderProcessor;
    BuyUnlockedProcessor directBuyIssuerImplementation;
    BuyUnlockedProcessor directBuyIssuer;
    Forwarder forwarder;
    DividendDistribution dividendDistributor;
}

library DeployAllLib {
    function deployAll(DeployAllConfig memory cfg, Fees memory fees) internal returns (Deployments memory) {
        Deployments memory deployments;

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

        // deploy vault and fulfillment router

        deployments.vault = new Vault(cfg.deployer);
        deployments.fulfillmentRouter = new FulfillmentRouter(cfg.deployer);

        // config vault and fulfillment router
        deployments.vault.grantRole(deployments.vault.OPERATOR_ROLE(), address(deployments.fulfillmentRouter));
        deployments.fulfillmentRouter.grantRole(deployments.fulfillmentRouter.OPERATOR_ROLE(), cfg.operator);
        deployments.fulfillmentRouter.grantRole(deployments.fulfillmentRouter.OPERATOR_ROLE(), cfg.operator2);

        // deploy blacklist prechecker
        deployments.tokenLockCheck = new TokenLockCheck(address(0), address(0));

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
        deployments.orderProcessor.grantRole(
            deployments.orderProcessor.OPERATOR_ROLE(), address(deployments.fulfillmentRouter)
        );
        deployments.directBuyIssuer.grantRole(
            deployments.directBuyIssuer.OPERATOR_ROLE(), address(deployments.fulfillmentRouter)
        );

        /// ------------------ forwarder ------------------

        deployments.forwarder = new Forwarder(cfg.ethusdoracle, fees.sellGasCost);
        deployments.forwarder.setFeeBps(fees.forwarderFee);

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

        /// ------------------ configure payment tokens ------------------

        OrderProcessor.FeeRates memory defaultFees = OrderProcessor.FeeRates({
            perOrderFeeBuy: fees.perOrderFee,
            percentageFeeRateBuy: fees.percentageFeeRate,
            perOrderFeeSell: fees.perOrderFee,
            percentageFeeRateSell: fees.percentageFeeRate
        });

        for (uint256 i = 0; i < cfg.paymentTokens.length; i++) {
            PaymentTokenConfig memory paymentToken = cfg.paymentTokens[i];
            deployments.tokenLockCheck.setCallSelector(paymentToken.token, paymentToken.isBlacklistedSelector);

            deployments.orderProcessor.setDefaultFees(paymentToken.token, defaultFees);
            deployments.directBuyIssuer.setDefaultFees(paymentToken.token, defaultFees);

            deployments.forwarder.setPaymentOracle(paymentToken.token, paymentToken.oracle);
        }

        return deployments;
    }
}
