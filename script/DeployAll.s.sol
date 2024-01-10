// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {OrderProcessor} from "../src/orders/OrderProcessor.sol";
import {TokenLockCheck, ITokenLockCheck, IERC20Usdc} from "../src/TokenLockCheck.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployAllScript is Script {
    struct DeployConfig {
        address deployer;
        // address owner;
        address treasury;
        address operator;
        address operator2;
        address usdc;
        address usdt;
        address relayer;
        address oracle;
    }

    // Tether
    mapping(address => bool) public isBlocked;

    uint64 constant perOrderFee = 1 ether;
    uint24 constant percentageFeeRate = 5_000;
    uint256 constant SELL_GAS_COST = 1000000;

    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        // uint256 ownerKey = vm.envUint("OWNER_KEY");
        DeployConfig memory cfg = DeployConfig({
            deployer: vm.addr(deployerPrivateKey),
            // owner: vm.addr(ownerKey),
            treasury: vm.envAddress("TREASURY"),
            operator: vm.envAddress("OPERATOR"),
            operator2: vm.envAddress("OPERATOR2"),
            usdc: vm.envAddress("USDC"),
            usdt: vm.envAddress("USDT"),
            // usdt: address(0),
            relayer: vm.envAddress("RELAYER"),
            oracle: vm.envAddress("ORACLE")
        });
        address usdcoracle = vm.envAddress("USDCORACLE");
        address usdtoracle = vm.envAddress("USDTORACLE");
        address ethusdoracle = vm.envAddress("ETHUSDORACLE");

        address usdce = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

        console.log("deployer: %s", cfg.deployer);
        // console.log("owner: %s", cfg.owner);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        /// ------------------ order processors ------------------

        // deploy blacklist prechecker
        TokenLockCheck tokenLockCheck = new TokenLockCheck(cfg.usdc, address(0));
        // add USDC.e
        tokenLockCheck.setCallSelector(usdce, IERC20Usdc.isBlacklisted.selector);
        // add USDT.e
        tokenLockCheck.setCallSelector(cfg.usdt, this.isBlocked.selector);

        OrderProcessor orderProcessorImpl = new OrderProcessor();
        OrderProcessor orderProcessor = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(orderProcessorImpl),
                    abi.encodeCall(OrderProcessor.initialize, (cfg.deployer, cfg.treasury, tokenLockCheck))
                )
            )
        );

        // config operator
        orderProcessor.grantRole(orderProcessor.OPERATOR_ROLE(), cfg.operator);
        orderProcessor.grantRole(orderProcessor.OPERATOR_ROLE(), cfg.operator2);

        // config payment token
        OrderProcessor.FeeRates memory defaultFees = OrderProcessor.FeeRates({
            perOrderFeeBuy: perOrderFee,
            percentageFeeRateBuy: percentageFeeRate,
            perOrderFeeSell: perOrderFee,
            percentageFeeRateSell: percentageFeeRate
        });

        orderProcessor.setDefaultFees(cfg.usdc, defaultFees);

        orderProcessor.setDefaultFees(cfg.usdt, defaultFees);

        orderProcessor.setDefaultFees(usdce, defaultFees);

        /// ------------------ dividend distributor ------------------

        // new DividendDistribution(cfg.deployer);

        // add dividend operator

        /// ------------------ dShares ------------------

        // transfer ownership
        // orderProcessor.beginDefaultAdminTransfer(owner);
        // directBuyIssuer.beginDefaultAdminTransfer(owner);

        vm.stopBroadcast();

        // // accept ownership transfer
        // vm.startBroadcast(owner);

        // orderProcessor.acceptDefaultAdminTransfer();
        // directBuyIssuer.acceptDefaultAdminTransfer();

        // vm.stopBroadcast();
    }
}
