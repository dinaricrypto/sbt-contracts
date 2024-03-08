// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {MockToken} from "../test/utils/mocks/MockToken.sol";
import {Vault} from "../src/orders/Vault.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {DShare} from "../src/DShare.sol";
import {WrappedDShare} from "../src/WrappedDShare.sol";
import {TokenLockCheck} from "../src/TokenLockCheck.sol";
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
        address ethusdoracle;
        address usdcoracle;
        address usdtoracle;
    }

    struct Deployments {
        MockToken usdc;
        MockToken usdt;
        MockToken usdce;
        Vault vault;
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
            ethusdoracle: vm.envAddress("ETHUSDORACLE"),
            usdcoracle: vm.envAddress("USDCORACLE"),
            usdtoracle: vm.envAddress("USDTORACLE")
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

        // vault
        deployments.vault = new Vault(cfg.deployer);
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
                    abi.encodeCall(
                        OrderProcessor.initialize,
                        (
                            cfg.deployer,
                            cfg.treasury,
                            address(deployments.vault),
                            deployments.dShareFactory,
                            deployments.tokenLockCheck,
                            cfg.ethusdoracle
                        )
                    )
                )
            )
        );

        // config operator
        deployments.orderProcessor.setOperator(cfg.operator, true);

        // config payment token
        deployments.orderProcessor.setFees(
            address(0), address(deployments.usdc), perOrderFee, percentageFeeRate, perOrderFee, percentageFeeRate
        );
        deployments.orderProcessor.setPaymentTokenOracle(address(deployments.usdc), cfg.usdcoracle);

        deployments.orderProcessor.setFees(
            address(0), address(deployments.usdt), perOrderFee, percentageFeeRate, perOrderFee, percentageFeeRate
        );
        deployments.orderProcessor.setPaymentTokenOracle(address(deployments.usdt), cfg.usdtoracle);

        deployments.orderProcessor.setFees(
            address(0), address(deployments.usdce), perOrderFee, percentageFeeRate, perOrderFee, percentageFeeRate
        );
        deployments.orderProcessor.setPaymentTokenOracle(address(deployments.usdce), cfg.usdcoracle);

        /// ------------------ dividend distributor ------------------

        deployments.dividendDistributor = new DividendDistribution(cfg.deployer);

        // add distributor
        deployments.dividendDistributor.grantRole(deployments.dividendDistributor.DISTRIBUTOR_ROLE(), cfg.distributor);

        vm.stopBroadcast();
    }
}
