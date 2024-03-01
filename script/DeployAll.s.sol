// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {TokenLockCheck, ITokenLockCheck, IERC20Usdc} from "../src/TokenLockCheck.sol";
import {ForwarderPyth} from "../src/forwarder/ForwarderPyth.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
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
    }

    // Tether
    mapping(address => bool) public isBlocked;

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
            // usdb: vm.envAddress("USDB")
            usdb: address(0)
        });
        address pyth = vm.envAddress("PYTH");
        bytes32 ethusdoracleid = vm.envBytes32("ETHUSDORACLEID");

        console.log("deployer: %s", cfg.deployer);
        // console.log("owner: %s", cfg.owner);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        // deploy mock USDC with 6 decimals
        cfg.usdb = address(new MockToken("USB Coin - Dinari", "USDB"));

        /// ------------------ order processors ------------------

        // deploy blacklist prechecker
        TokenLockCheck tokenLockCheck = new TokenLockCheck();

        OrderProcessor orderProcessorImpl = new OrderProcessor();
        OrderProcessor orderProcessor = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(orderProcessorImpl),
                    abi.encodeCall(OrderProcessor.initialize, (cfg.deployer, cfg.treasury, tokenLockCheck))
                )
            )
        );

        BuyUnlockedProcessor directBuyIssuerImpl = new BuyUnlockedProcessor();
        BuyUnlockedProcessor directBuyIssuer = BuyUnlockedProcessor(
            address(
                new ERC1967Proxy(
                    address(directBuyIssuerImpl),
                    abi.encodeCall(OrderProcessor.initialize, (cfg.deployer, cfg.treasury, tokenLockCheck))
                )
            )
        );

        // config operator
        orderProcessor.grantRole(orderProcessor.OPERATOR_ROLE(), cfg.operator);
        directBuyIssuer.grantRole(directBuyIssuer.OPERATOR_ROLE(), cfg.operator);
        orderProcessor.grantRole(orderProcessor.OPERATOR_ROLE(), cfg.operator2);
        directBuyIssuer.grantRole(directBuyIssuer.OPERATOR_ROLE(), cfg.operator2);

        // config payment token
        OrderProcessor.FeeRates memory defaultFees = OrderProcessor.FeeRates({
            perOrderFeeBuy: 1 ether,
            percentageFeeRateBuy: 0,
            perOrderFeeSell: 1 ether,
            percentageFeeRateSell: 5_000
        });

        orderProcessor.setDefaultFees(cfg.usdb, defaultFees);
        directBuyIssuer.setDefaultFees(cfg.usdb, defaultFees);

        /// ------------------ forwarder ------------------

        ForwarderPyth forwarder = new ForwarderPyth(pyth, ethusdoracleid, SELL_GAS_COST);

        forwarder.setPaymentOracle(cfg.usdb, bytes32(uint256(1)));

        forwarder.setSupportedModule(address(orderProcessor), true);
        forwarder.setSupportedModule(address(directBuyIssuer), true);

        forwarder.setRelayer(cfg.relayer, true);

        orderProcessor.grantRole(orderProcessor.FORWARDER_ROLE(), address(forwarder));
        directBuyIssuer.grantRole(directBuyIssuer.FORWARDER_ROLE(), address(forwarder));

        /// ------------------ dividend distributor ------------------

        DividendDistribution dividendDistributor = new DividendDistribution(cfg.deployer);

        // add dividend operator
        dividendDistributor.grantRole(dividendDistributor.DISTRIBUTOR_ROLE(), cfg.distributor);

        vm.stopBroadcast();
    }
}
