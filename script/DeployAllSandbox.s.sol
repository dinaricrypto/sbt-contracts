// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {MockToken} from "../test/utils/mocks/MockToken.sol";
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
        OrderProcessor orderProcessorImplementation;
        OrderProcessor orderProcessor;
        Vault vault;
        FulfillmentRouter fulfillmentRouter;
        DividendDistribution dividendDistributor;
    }

    uint64 constant perOrderFee = 1 ether;
    uint24 constant percentageFeeRate = 5_000;

    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");

        DeployConfig memory cfg = DeployConfig({
            deployer: vm.addr(deployerPrivateKey),
            treasury: vm.envAddress("TREASURY"),
            operator: vm.envAddress("OPERATOR"),
            distributor: vm.envAddress("DISTRIBUTOR"),
            relayer: vm.envAddress("RELAYER")
        });

        Deployments memory deployments;

        console.log("deployer: %s", cfg.deployer);

        bytes32 salt = keccak256(abi.encodePacked(cfg.deployer));

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
        deployments.transferRestrictor = new TransferRestrictor{salt: salt}(cfg.deployer);

        // deploy dShares logic implementation
        deployments.dShareImplementation = address(new DShare{salt: salt}());

        // deploy dShares beacon
        deployments.dShareBeacon = new UpgradeableBeacon{salt: salt}(deployments.dShareImplementation, cfg.deployer);

        // deploy wrapped dShares logic implementation
        deployments.wrappeddShareImplementation = address(new WrappedDShare{salt: salt}());

        // deploy wrapped dShares beacon
        deployments.wrappeddShareBeacon =
            new UpgradeableBeacon{salt: salt}(deployments.wrappeddShareImplementation, cfg.deployer);

        // deploy dShare factory
        deployments.dShareFactoryImplementation = address(new DShareFactory{salt: salt}());

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

        /// ------------------ order processors ------------------

        // vault
        deployments.vault = new Vault{salt: salt}(cfg.deployer);

        deployments.orderProcessorImplementation = OrderProcessor(address(new OrderProcessor{salt: salt}()));
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

        // fulfillment router
        deployments.fulfillmentRouter = new FulfillmentRouter(cfg.deployer);

        // config operator
        deployments.orderProcessor.setOperator(address(deployments.fulfillmentRouter), true);
        deployments.fulfillmentRouter.grantRole(deployments.fulfillmentRouter.OPERATOR_ROLE(), cfg.operator);

        // config payment token
        deployments.orderProcessor.setPaymentToken(
            address(deployments.usdc),
            deployments.usdc.isBlacklisted.selector,
            perOrderFee,
            percentageFeeRate,
            perOrderFee,
            percentageFeeRate
        );

        deployments.orderProcessor.setPaymentToken(
            address(deployments.usdt),
            deployments.usdt.isBlacklisted.selector,
            perOrderFee,
            percentageFeeRate,
            perOrderFee,
            percentageFeeRate
        );

        deployments.orderProcessor.setPaymentToken(
            address(deployments.usdce),
            deployments.usdce.isBlacklisted.selector,
            perOrderFee,
            percentageFeeRate,
            perOrderFee,
            percentageFeeRate
        );

        /// ------------------ dividend distributor ------------------

        deployments.dividendDistributor = new DividendDistribution{salt: salt}(cfg.deployer);

        // add distributor
        deployments.dividendDistributor.grantRole(deployments.dividendDistributor.DISTRIBUTOR_ROLE(), cfg.distributor);

        vm.stopBroadcast();
    }
}
