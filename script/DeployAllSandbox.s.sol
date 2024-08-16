// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
// import {MockToken} from "../test/utils/mocks/MockToken.sol";
import {Vault} from "../src/orders/Vault.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {DShare} from "../src/DShare.sol";
import {WrappedDShare} from "../src/WrappedDShare.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";
import {DShareFactory} from "../src/DShareFactory.sol";
import {Vault} from "../src/orders/Vault.sol";
import {FulfillmentRouter} from "../src/orders/FulfillmentRouter.sol";
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
        address paymentToken;
    }

    struct Deployments {
        Vault vault;
        TransferRestrictor transferRestrictor;
        address dShareImplementation;
        UpgradeableBeacon dShareBeacon;
        address wrappeddShareImplementation;
        UpgradeableBeacon wrappeddShareBeacon;
        address dShareFactoryImplementation;
        DShareFactory dShareFactory;
        OrderProcessor orderProcessorImplementation;
        OrderProcessor orderProcessor;
        Vault vault;
        FulfillmentRouter fulfillmentRouter;
        DividendDistribution dividendDistributor;
    }

    uint64 constant perOrderFee = 1e8;
    uint24 constant percentageFeeRate = 5_000;

    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");

        DeployConfig memory cfg = DeployConfig({
            deployer: vm.addr(deployerPrivateKey),
            treasury: vm.envAddress("TREASURY"),
            operator: vm.envAddress("OPERATOR"),
            distributor: vm.envAddress("DISTRIBUTOR"),
            relayer: vm.envAddress("RELAYER"),
            paymentToken: vm.envAddress("GNUSD")
        });

        Deployments memory deployments;

        console.log("deployer: %s", cfg.deployer);

        bytes32 salt = keccak256(abi.encodePacked("0.4.1pre1"));

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        /// ------------------ asset tokens ------------------

        // deploy transfer restrictor
        deployments.transferRestrictor = new TransferRestrictor{salt: salt}(cfg.deployer);
        console.log("transfer restrictor: %s", address(deployments.transferRestrictor));

        // deploy dShares logic implementation
        deployments.dShareImplementation = address(new DShare{salt: salt}());
        console.log("dShare implementation: %s", deployments.dShareImplementation);

        // deploy dShares beacon
        deployments.dShareBeacon = new UpgradeableBeacon{salt: salt}(deployments.dShareImplementation, cfg.deployer);
        console.log("dShare beacon: %s", address(deployments.dShareBeacon));

        // deploy wrapped dShares logic implementation
        deployments.wrappeddShareImplementation = address(new WrappedDShare{salt: salt}());
        console.log("wrapped dShare implementation: %s", deployments.wrappeddShareImplementation);

        // deploy wrapped dShares beacon
        deployments.wrappeddShareBeacon =
            new UpgradeableBeacon{salt: salt}(deployments.wrappeddShareImplementation, cfg.deployer);
        console.log("wrapped dShare beacon: %s", address(deployments.wrappeddShareBeacon));

        // deploy dShare factory
        deployments.dShareFactoryImplementation = address(new DShareFactory{salt: salt}());
        console.log("dShare factory implementation: %s", deployments.dShareFactoryImplementation);

        deployments.dShareFactory = DShareFactory(
            address(
                new ERC1967Proxy{salt: salt}(
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
        console.log("dShare factory: %s", address(deployments.dShareFactory));

        /// ------------------ order processors ------------------

        // vault
        deployments.vault = new Vault{salt: salt}(cfg.deployer);
        console.log("vault: %s", address(deployments.vault));

        deployments.orderProcessorImplementation = OrderProcessor(address(new OrderProcessor{salt: salt}()));
        console.log("order processor implementation: %s", address(deployments.orderProcessorImplementation));
        deployments.orderProcessor = OrderProcessor(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(deployments.orderProcessorImplementation),
                    abi.encodeCall(
                        OrderProcessor.initialize,
                        (cfg.deployer, cfg.treasury, address(deployments.vault), deployments.dShareFactory)
                    )
                )
            )
        );
        console.log("order processor: %s", address(deployments.orderProcessor));

        // fulfillment router
        deployments.fulfillmentRouter = new FulfillmentRouter(cfg.deployer);

        // config operator
        deployments.orderProcessor.setOperator(address(deployments.fulfillmentRouter), true);
        deployments.fulfillmentRouter.grantRole(deployments.fulfillmentRouter.OPERATOR_ROLE(), cfg.operator);

        // config payment token
        deployments.orderProcessor.setPaymentToken(
            cfg.paymentToken, bytes4(0), perOrderFee, percentageFeeRate, perOrderFee, percentageFeeRate
        );

        /// ------------------ dividend distributor ------------------

        deployments.dividendDistributor = new DividendDistribution{salt: salt}(cfg.deployer);
        console.log("dividend distributor: %s", address(deployments.dividendDistributor));

        // add distributor
        deployments.dividendDistributor.grantRole(deployments.dividendDistributor.DISTRIBUTOR_ROLE(), cfg.distributor);

        vm.stopBroadcast();
    }
}
