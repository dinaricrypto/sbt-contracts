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

        // config operator
        deployments.orderProcessor.setOperator(cfg.operator, true);

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

//  deployer: 0x702347E2B1be68444C1451922275b66AABDaC528
//  transfer restrictor: 0x585b916116631A5310f224F146f2F6ffb8FE656E
//  dShare implementation: 0xE4Ff8Bf2d94f578C25E9b0aA6f5071800Ee0375F
//  dShare beacon: 0x338e7708C5ee50d08A3fa13D67a569a07c99dF16
//  wrapped dShare implementation: 0x8316f45Da92c3b9A032095c5F383E9f0f7361f4C
//  wrapped dShare beacon: 0x94E0555B92E3907f6598b68Bc82c33079C8850Af
//  dShare factory implementation: 0x638c2Fa8B02E8F294e8Af9d7F2248Ec1E085aa79
//  dShare factory: 0xaa5474bbb3aec03B81D1E280c821dBeF60A7aABe
//  vault: 0x3934aeeE752235AEe8139dbeC4493639534EFf2D
//  order processor implementation: 0x897627378772f7139Dda8fD16602019aA6d557F2
//  order processor: 0x94902a03f7E27c6f512B3E1E8cc7b1e1d2CCeE63
//  dividend distributor: 0x0F96bf4a333ab9f46B7bA9B873B99F6022798Aa5
