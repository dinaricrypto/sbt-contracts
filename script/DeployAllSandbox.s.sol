// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {MockToken} from "../test/utils/mocks/MockToken.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {dShare} from "../src/dShare.sol";
import {WrappeddShare} from "../src/WrappeddShare.sol";
import {TokenLockCheck} from "../src/TokenLockCheck.sol";
import {EscrowOrderProcessor} from "../src/orders/EscrowOrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {Forwarder} from "../src/forwarder/Forwarder.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";

contract DeployAllSandboxScript is Script {
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
        dShare[] dShares;
        address wrappeddShareImplementation;
        UpgradeableBeacon wrappeddShareBeacon;
        WrappeddShare[] wrappeddShares;
        TokenLockCheck tokenLockCheck;
        EscrowOrderProcessor escrowOrderProcessor;
        BuyUnlockedProcessor directBuyIssuer;
        Forwarder forwarder;
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
            relayer: vm.envAddress("RELAYER"),
            ethusdoracle: vm.envAddress("ETHUSDORACLE"),
            usdcoracle: vm.envAddress("USDCORACLE")
        });

        Deployments memory deployments;

        console.log("deployer: %s", cfg.deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        /// ------------------ payment tokens ------------------

        // deploy mock USDC with 6 decimals
        deployments.usdc = new MockToken("USD Coin", "USDC");
        // deploy mock USDT with 6 decimals
        deployments.usdt = new MockToken("Tether USD", "USDT");
        // deploy mock USDC.e with 6 decimals
        deployments.usdce = new MockToken("USD Coin - Dinari", "USDC.e");

        /// ------------------ asset tokens ------------------

        // deploy transfer restrictor
        deployments.transferRestrictor = new TransferRestrictor(cfg.deployer);

        // deploy dShares logic implementation
        deployments.dShareImplementation = address(new dShare());

        // deploy dShares beacon
        deployments.dShareBeacon = new UpgradeableBeacon(deployments.dShareImplementation, cfg.deployer);

        // deploy wrapped dShares logic implementation
        deployments.wrappeddShareImplementation = address(new WrappeddShare());

        // deploy wrapped dShares beacon
        deployments.wrappeddShareBeacon = new UpgradeableBeacon(deployments.wrappeddShareImplementation, cfg.deployer);

        string[] memory dShareNames = new string[](13);
        dShareNames[0] = "Tesla, Inc.";
        dShareNames[1] = "NVIDIA Corporation";
        dShareNames[2] = "Microsoft Corporation";
        dShareNames[3] = "Meta Platforms, Inc.";
        dShareNames[4] = "Netflix, Inc.";
        dShareNames[5] = "Apple Inc.";
        dShareNames[6] = "Alphabet Inc. Class A";
        dShareNames[7] = "Amazon.com, Inc.";
        dShareNames[8] = "PayPal Holdings, Inc.";
        dShareNames[9] = "Pfizer, Inc.";
        dShareNames[10] = "The Walt Disney Company";
        dShareNames[11] = "SPDR S&P 500 ETF Trust";
        dShareNames[12] = "WisdomTree Floating Rate Treasury Fund";

        string[] memory dShareSymbols = new string[](13);
        dShareSymbols[0] = "TSLA.d";
        dShareSymbols[1] = "NVDA.d";
        dShareSymbols[2] = "MSFT.d";
        dShareSymbols[3] = "META.d";
        dShareSymbols[4] = "NFLX.d";
        dShareSymbols[5] = "AAPL.d";
        dShareSymbols[6] = "GOOGL.d";
        dShareSymbols[7] = "AMZN.d";
        dShareSymbols[8] = "PYPL.d";
        dShareSymbols[9] = "PFE.d";
        dShareSymbols[10] = "DIS.d";
        dShareSymbols[11] = "SPY.d";
        dShareSymbols[12] = "USFR.d";

        deployments.dShares = new dShare[](13);
        deployments.wrappeddShares = new WrappeddShare[](13);

        for (uint256 i = 0; i < deployments.dShares.length; i++) {
            // deploy dShare
            deployments.dShares[i] = dShare(
                address(
                    new BeaconProxy(
                        address(deployments.dShareBeacon),
                        abi.encodeCall(
                            dShare.initialize,
                            (cfg.deployer, dShareNames[i], dShareSymbols[i], deployments.transferRestrictor)
                        )
                    )
                )
            );
            // deploy wrapped dShare
            deployments.wrappeddShares[i] = WrappeddShare(
                address(
                    new BeaconProxy(
                        address(deployments.wrappeddShareBeacon),
                        abi.encodeCall(
                            WrappeddShare.initialize,
                            (
                                cfg.deployer,
                                deployments.dShares[i],
                                string.concat("Wrapped ", dShareNames[i]),
                                string.concat("w", dShareSymbols[i])
                            )
                        )
                    )
                )
            );
        }

        /// ------------------ order processors ------------------

        // deploy blacklist prechecker
        deployments.tokenLockCheck = new TokenLockCheck(address(0), address(0));
        // add USDC
        deployments.tokenLockCheck.setCallSelector(address(deployments.usdc), deployments.usdc.isBlacklisted.selector);
        // add USDT.e
        deployments.tokenLockCheck.setCallSelector(address(deployments.usdt), deployments.usdt.isBlocked.selector);
        // add USDC.e
        deployments.tokenLockCheck.setCallSelector(address(deployments.usdce), deployments.usdce.isBlacklisted.selector);

        deployments.escrowOrderProcessor = new EscrowOrderProcessor(
            cfg.deployer, cfg.treasury, perOrderFee, percentageFeeRate, deployments.tokenLockCheck
        );

        deployments.directBuyIssuer = new BuyUnlockedProcessor(
            cfg.deployer, cfg.treasury, perOrderFee, percentageFeeRate, deployments.tokenLockCheck
        );

        // config operator
        deployments.escrowOrderProcessor.grantRole(deployments.escrowOrderProcessor.OPERATOR_ROLE(), cfg.operator);
        deployments.directBuyIssuer.grantRole(deployments.directBuyIssuer.OPERATOR_ROLE(), cfg.operator);

        // config payment token
        deployments.escrowOrderProcessor.grantRole(
            deployments.escrowOrderProcessor.PAYMENTTOKEN_ROLE(), address(deployments.usdc)
        );
        deployments.directBuyIssuer.grantRole(
            deployments.directBuyIssuer.PAYMENTTOKEN_ROLE(), address(deployments.usdc)
        );

        deployments.escrowOrderProcessor.grantRole(
            deployments.escrowOrderProcessor.PAYMENTTOKEN_ROLE(), address(deployments.usdt)
        );
        deployments.directBuyIssuer.grantRole(
            deployments.directBuyIssuer.PAYMENTTOKEN_ROLE(), address(deployments.usdt)
        );

        deployments.escrowOrderProcessor.grantRole(
            deployments.escrowOrderProcessor.PAYMENTTOKEN_ROLE(), address(deployments.usdce)
        );
        deployments.directBuyIssuer.grantRole(
            deployments.directBuyIssuer.PAYMENTTOKEN_ROLE(), address(deployments.usdce)
        );

        // config asset token
        for (uint256 i = 0; i < deployments.dShares.length; i++) {
            deployments.tokenLockCheck.setCallSelector(
                address(deployments.dShares[i]), deployments.dShares[i].isBlacklisted.selector
            );

            deployments.escrowOrderProcessor.grantRole(
                deployments.escrowOrderProcessor.ASSETTOKEN_ROLE(), address(deployments.dShares[i])
            );
            deployments.directBuyIssuer.grantRole(
                deployments.directBuyIssuer.ASSETTOKEN_ROLE(), address(deployments.dShares[i])
            );

            deployments.dShares[i].grantRole(
                deployments.dShares[i].MINTER_ROLE(), address(deployments.escrowOrderProcessor)
            );
            deployments.dShares[i].grantRole(
                deployments.dShares[i].BURNER_ROLE(), address(deployments.escrowOrderProcessor)
            );
            deployments.dShares[i].grantRole(deployments.dShares[i].MINTER_ROLE(), address(deployments.directBuyIssuer));
        }

        /// ------------------ forwarder ------------------

        deployments.forwarder = new Forwarder(cfg.ethusdoracle);
        deployments.forwarder.setFeeBps(2000);

        deployments.forwarder.setPaymentOracle(address(deployments.usdc), cfg.usdcoracle);
        deployments.forwarder.setPaymentOracle(address(deployments.usdce), cfg.usdcoracle);
        deployments.forwarder.setPaymentOracle(address(deployments.usdt), cfg.usdcoracle);

        deployments.forwarder.setSupportedModule(address(deployments.escrowOrderProcessor), true);
        deployments.forwarder.setSupportedModule(address(deployments.directBuyIssuer), true);

        deployments.forwarder.setRelayer(cfg.relayer, true);

        deployments.escrowOrderProcessor.grantRole(
            deployments.escrowOrderProcessor.FORWARDER_ROLE(), address(deployments.forwarder)
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
