// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {TransferRestrictor} from "../../src/TransferRestrictor.sol";
import {DShare} from "../../src/DShare.sol";
import {WrappedDShare} from "../../src/WrappedDShare.sol";
import {OrderProcessor} from "../../src/orders/OrderProcessor.sol";
import {DividendDistribution} from "../../src/dividend/DividendDistribution.sol";
import {DShareFactory} from "../../src/DShareFactory.sol";
import {Vault} from "../../src/orders/Vault.sol";
import {FulfillmentRouter} from "../../src/orders/FulfillmentRouter.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployAllCreate2 is Script {
    struct Deployments {
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

    string constant version = "0.4.0";

    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address owner = vm.envAddress("OWNER");
        string memory environmentName = vm.envString("ENVIRONMENT");
        address treasury = vm.envAddress("TREASURY");

        Deployments memory deployments;

        console.log("environment: %s", environmentName);
        console.log("deployer: %s", deployer);
        console.log("owner: %s", owner);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        /// ------------------ asset tokens ------------------

        // deploy transfer restrictor
        deployments.transferRestrictor = new TransferRestrictor{
            salt: keccak256(abi.encode(string.concat("TransferRestrictor", environmentName, version)))
        }(owner);
        console.log("transferRestrictor: %s", address(deployments.transferRestrictor));

        // deploy dShares logic implementation
        deployments.dShareImplementation =
            address(new DShare{salt: keccak256(abi.encode(string.concat("DShare", environmentName, version)))}());
        console.log("dShareImplementation: %s", address(deployments.dShareImplementation));

        // deploy dShares beacon
        deployments.dShareBeacon = new UpgradeableBeacon{
            salt: keccak256(abi.encode(string.concat("DShareBeacon", environmentName, version)))
        }(deployments.dShareImplementation, owner);
        console.log("dShareBeacon: %s", address(deployments.dShareBeacon));

        // deploy wrapped dShares logic implementation
        deployments.wrappeddShareImplementation = address(
            new WrappedDShare{salt: keccak256(abi.encode(string.concat("WrappedDShare", environmentName, version)))}()
        );
        console.log("wrappeddShareImplementation: %s", address(deployments.wrappeddShareImplementation));

        // deploy wrapped dShares beacon
        deployments.wrappeddShareBeacon = new UpgradeableBeacon{
            salt: keccak256(abi.encode(string.concat("WrappedDShareBeacon", environmentName, version)))
        }(deployments.wrappeddShareImplementation, owner);
        console.log("wrappeddShareBeacon: %s", address(deployments.wrappeddShareBeacon));

        // deploy dShare factory
        deployments.dShareFactoryImplementation = address(
            new DShareFactory{salt: keccak256(abi.encode(string.concat("DShareFactory", environmentName, version)))}()
        );
        console.log("dShareFactoryImplementation: %s", address(deployments.dShareFactoryImplementation));

        deployments.dShareFactory = DShareFactory(
            address(
                new ERC1967Proxy{
                    salt: keccak256(abi.encode(string.concat("DShareFactoryProxy", environmentName, version)))
                }(
                    deployments.dShareFactoryImplementation,
                    abi.encodeCall(
                        DShareFactory.initialize,
                        (
                            owner,
                            address(deployments.dShareBeacon),
                            address(deployments.wrappeddShareBeacon),
                            address(deployments.transferRestrictor)
                        )
                    )
                )
            )
        );
        console.log("dShareFactory: %s", address(deployments.dShareFactory));

        /// ------------------ order processors ------------------

        // vault
        deployments.vault =
            new Vault{salt: keccak256(abi.encode(string.concat("Vault", environmentName, version)))}(owner);
        console.log("vault: %s", address(deployments.vault));

        deployments.orderProcessorImplementation =
            new OrderProcessor{salt: keccak256(abi.encode(string.concat("OrderProcessor", environmentName, version)))}();
        console.log("orderProcessorImplementation: %s", address(deployments.orderProcessorImplementation));
        deployments.orderProcessor = OrderProcessor(
            address(
                new ERC1967Proxy{
                    salt: keccak256(abi.encode(string.concat("OrderProcessorProxy", environmentName, version)))
                }(
                    address(deployments.orderProcessorImplementation),
                    abi.encodeCall(
                        OrderProcessor.initialize,
                        (owner, treasury, address(deployments.vault), deployments.dShareFactory)
                    )
                )
            )
        );
        console.log("orderProcessor: %s", address(deployments.orderProcessor));

        // fulfillment router
        deployments.fulfillmentRouter = new FulfillmentRouter{
            salt: keccak256(abi.encode(string.concat("FulfillmentRouter", environmentName, version)))
        }(owner);
        console.log("fulfillmentRouter: %s", address(deployments.fulfillmentRouter));

        /// ------------------ dividend distributor ------------------

        deployments.dividendDistributor = new DividendDistribution{
            salt: keccak256(abi.encode(string.concat("DividendDistribution", environmentName, version)))
        }(owner);

        vm.stopBroadcast();
    }
}
