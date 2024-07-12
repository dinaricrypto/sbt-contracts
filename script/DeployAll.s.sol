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
        // address operator;
        // address operator2;
        // address relayer;
        // address distributor;
        address usdc;
        address usdplus;
        // address pyth;
        // bytes32 ethusdoracleid;
    }

    struct Deployments {
        TransferRestrictor transferRestrictor;
        // address dShareImplementation;
        UpgradeableBeacon dShareBeacon;
        // address wrappeddShareImplementation;
        UpgradeableBeacon wrappeddShareBeacon;
        // address dShareFactoryImplementation;
        DShareFactory dShareFactory;
        TokenLockCheck tokenLockCheck;
        OrderProcessor orderProcessorImplementation;
        OrderProcessor orderProcessor;
        // BuyUnlockedProcessor directBuyIssuerImplementation;
        // BuyUnlockedProcessor directBuyIssuer;
        ForwarderPyth forwarder;
        FulfillmentRouter fulfillmentRouter;
        // Vault vault;
        // DividendDistribution dividendDistributor;
    }

    uint256 constant SELL_GAS_COST = 421_549;

    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        DeployConfig memory cfg = DeployConfig({
            deployer: vm.addr(deployerPrivateKey),
            treasury: vm.envAddress("TREASURY"),
            // operator: vm.envAddress("OPERATOR"),
            // operator2: vm.envAddress("OPERATOR2"),
            // relayer: vm.envAddress("RELAYER"),
            // distributor: vm.envAddress("DISTRIBUTOR"),
            usdc: vm.envAddress("USDC"),
            usdplus: vm.envAddress("USDPLUS")
            // pyth: vm.envAddress("PYTH"),
            // ethusdoracleid: vm.envBytes32("ETHUSDORACLEID")
        });

        Deployments memory deps;

        console.log("deployer: %s", cfg.deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        /// ------------------ asset tokens ------------------

        // deploy transfer restrictor
        deps.transferRestrictor = TransferRestrictor(0xa030E2a6f377E59704A585748897a1Ddc5963cB1);

        // deploy dShares beacon
        deps.dShareBeacon = UpgradeableBeacon(0x525783cb1f1ABA2FC5dFF884E6510a82704D3274);

        // deploy wrapped dShares beacon
        deps.wrappeddShareBeacon = UpgradeableBeacon(0xa5D5F87DA8B58Bd41514754738fAE4C8c4419FB0);

        deps.dShareFactory = DShareFactory(0x92289a641517BA65438605eF0EeCF5fFB08B597c);

        /// ------------------ order processors ------------------

        // deploy blacklist prechecker
        deps.tokenLockCheck = TokenLockCheck(0xDE9925851f41B4A405f7C8A44DdaB399D861dC5b);

        deps.orderProcessorImplementation = new OrderProcessor();
        deps.orderProcessor = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(deps.orderProcessorImplementation),
                    abi.encodeCall(OrderProcessor.initialize, (cfg.deployer, cfg.treasury, deps.tokenLockCheck))
                )
            )
        );

        // config payment token
        OrderProcessor.FeeRates memory defaultFees = OrderProcessor.FeeRates({
            perOrderFeeBuy: 1e8,
            percentageFeeRateBuy: 5_000,
            perOrderFeeSell: 1e8,
            percentageFeeRateSell: 5_000
        });

        deps.orderProcessor.setDefaultFees(cfg.usdc, defaultFees);
        deps.orderProcessor.setDefaultFees(cfg.usdplus, defaultFees);

        /// ------------------ forwarder ------------------

        deps.forwarder = ForwarderPyth(0xDfC5441EF5eEbf7bFa73B5420C57F42CC84f1B7f);

        deps.forwarder.setSupportedModule(address(deps.orderProcessor), true);

        deps.orderProcessor.grantRole(deps.orderProcessor.FORWARDER_ROLE(), address(deps.forwarder));

        /// ------------------ vault ------------------

        deps.fulfillmentRouter = FulfillmentRouter(0x8E65Ac7f98bb0D643DDb1C00A9d3e9292690A39b);
        deps.orderProcessor.grantRole(deps.orderProcessor.OPERATOR_ROLE(), address(deps.fulfillmentRouter));

        vm.stopBroadcast();
    }
}
