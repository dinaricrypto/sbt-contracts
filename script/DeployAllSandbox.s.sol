// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {MockToken} from "../test/utils/mocks/MockToken.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {dShare} from "../src/dShare.sol";

import {TokenLockCheck} from "../src/TokenLockCheck.sol";
import {BuyProcessor} from "../src/orders/BuyProcessor.sol";
import {SellProcessor} from "../src/orders/SellProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {Forwarder} from "../src/forwarder/Forwarder.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";

contract DeployAllSandboxScript is Script {
    struct DeployConfig {
        address deployer;
        address treasury;
        address operator;
        address distributor;
        address relayer;
    }

    uint64 constant perOrderFee = 1 ether;
    uint24 constant percentageFeeRate = 5_000;

    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("S_DEPLOY_KEY");

        DeployConfig memory cfg = DeployConfig({
            deployer: vm.addr(deployerPrivateKey),
            treasury: vm.envAddress("S_TREASURY"),
            operator: vm.envAddress("S_OPERATOR"),
            distributor: vm.envAddress("S_DISTRIBUTOR"),
            relayer: vm.envAddress("S_RELAYER")
        });

        console.log("deployer: %s", cfg.deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        /// ------------------ payment tokens ------------------

        // deploy mock USDC with 6 decimals
        MockToken usdc = new MockToken("USD Coin", "USDC");

        // deploy mock USDT with 6 decimals
        MockToken usdt = new MockToken("Tether USD", "USDT");

        // deploy mock USDC.e with 6 decimals
        MockToken usdce = new MockToken("USD Coin.e", "USDC.e");

        /// ------------------ asset tokens ------------------

        // deploy transfer restrictor
        TransferRestrictor transferRestrictor = new TransferRestrictor(cfg.deployer);

        dShare[] memory dShares = new dShare[](13);

        // deploy TSLA dShare
        dShares[0] = new dShare(cfg.deployer, "Tesla, Inc.", "TSLA.d", "", transferRestrictor);
        // deploy NVDA dShare
        dShares[1] = new dShare(cfg.deployer, "NVIDIA Corporation", "NVDA.d", "", transferRestrictor);
        // deploy MSFT dShare
        dShares[2] = new dShare(cfg.deployer, "Microsoft Corporation", "MSFT.d", "", transferRestrictor);
        // deploy META dShare
        dShares[3] = new dShare(cfg.deployer, "Meta Platforms, Inc.", "META.d", "", transferRestrictor);
        // deploy NFLX dShare
        dShares[4] = new dShare(cfg.deployer, "Netflix, Inc.", "NFLX.d", "", transferRestrictor);
        // deploy AAPL dShare
        dShares[5] = new dShare(cfg.deployer, "Apple Inc.", "AAPL.d", "", transferRestrictor);
        // deploy GOOGL dShare
        dShares[6] = new dShare(cfg.deployer, "Alphabet Inc. Class A", "GOOGL.d", "", transferRestrictor);
        // deploy AMZN dShare
        dShares[7] = new dShare(cfg.deployer, "Amazon.com, Inc.", "AMZN.d", "", transferRestrictor);
        // deploy PYPL dShare
        dShares[8] = new dShare(cfg.deployer, "PayPal Holdings, Inc.", "PYPL.d", "", transferRestrictor);
        // deploy PFE dShare
        dShares[9] = new dShare(cfg.deployer, "Pfizer, Inc.", "PFE.d", "", transferRestrictor);
        // deploy DIS dShare
        dShares[10] = new dShare(cfg.deployer, "The Walt Disney Company", "DIS.d", "", transferRestrictor);
        // deploy SPY dShare
        dShares[11] = new dShare(cfg.deployer, "SPDR S&P 500 ETF Trust", "SPY.d", "", transferRestrictor);
        // deploy USFR dShare
        dShares[12] =
            new dShare(cfg.deployer, "WisdomTree Floating Rate Treasury Fund", "USFR.d", "", transferRestrictor);

        /// ------------------ order processors ------------------

        // deploy blacklist prechecker
        TokenLockCheck tokenLockCheck = new TokenLockCheck(address(0), address(0));
        // add USDC
        tokenLockCheck.setCallSelector(address(usdc), usdc.isBlacklisted.selector);
        // add USDT.e
        tokenLockCheck.setCallSelector(address(usdt), usdt.isBlocked.selector);
        // add USDC.e
        tokenLockCheck.setCallSelector(address(usdce), usdce.isBlacklisted.selector);
        // add dShares
        for (uint256 i = 0; i < dShares.length; i++) {
            tokenLockCheck.setCallSelector(address(dShares[i]), dShares[i].isBlacklisted.selector);
        }

        BuyProcessor buyProcessor =
            new BuyProcessor(cfg.deployer, cfg.treasury, perOrderFee, percentageFeeRate, tokenLockCheck);

        SellProcessor sellProcessor =
            new SellProcessor(cfg.deployer, cfg.treasury, perOrderFee, percentageFeeRate, tokenLockCheck);

        BuyUnlockedProcessor directBuyIssuer =
            new BuyUnlockedProcessor(cfg.deployer, cfg.treasury, perOrderFee, percentageFeeRate, tokenLockCheck);

        // config operator
        buyProcessor.grantRole(buyProcessor.OPERATOR_ROLE(), cfg.operator);
        sellProcessor.grantRole(sellProcessor.OPERATOR_ROLE(), cfg.operator);
        directBuyIssuer.grantRole(directBuyIssuer.OPERATOR_ROLE(), cfg.operator);

        // config payment token
        buyProcessor.grantRole(buyProcessor.PAYMENTTOKEN_ROLE(), address(usdc));
        sellProcessor.grantRole(sellProcessor.PAYMENTTOKEN_ROLE(), address(usdc));
        directBuyIssuer.grantRole(directBuyIssuer.PAYMENTTOKEN_ROLE(), address(usdc));

        buyProcessor.grantRole(buyProcessor.PAYMENTTOKEN_ROLE(), address(usdt));
        sellProcessor.grantRole(sellProcessor.PAYMENTTOKEN_ROLE(), address(usdt));
        directBuyIssuer.grantRole(directBuyIssuer.PAYMENTTOKEN_ROLE(), address(usdt));

        buyProcessor.grantRole(buyProcessor.PAYMENTTOKEN_ROLE(), address(usdce));
        sellProcessor.grantRole(sellProcessor.PAYMENTTOKEN_ROLE(), address(usdce));
        directBuyIssuer.grantRole(directBuyIssuer.PAYMENTTOKEN_ROLE(), address(usdce));

        // config asset token
        for (uint256 i = 0; i < dShares.length; i++) {
            buyProcessor.grantRole(buyProcessor.ASSETTOKEN_ROLE(), address(dShares[i]));
            sellProcessor.grantRole(sellProcessor.ASSETTOKEN_ROLE(), address(dShares[i]));
            directBuyIssuer.grantRole(directBuyIssuer.ASSETTOKEN_ROLE(), address(dShares[i]));

            dShares[i].grantRole(dShares[i].MINTER_ROLE(), address(buyProcessor));
            dShares[i].grantRole(dShares[i].BURNER_ROLE(), address(sellProcessor));
            dShares[i].grantRole(dShares[i].MINTER_ROLE(), address(directBuyIssuer));
        }

        /// ------------------ forwarder ------------------

        Forwarder forwarder = new Forwarder();
        forwarder.setFeeBps(2000);

        forwarder.setSupportedModule(address(buyProcessor), true);
        forwarder.setSupportedModule(address(sellProcessor), true);
        forwarder.setSupportedModule(address(directBuyIssuer), true);

        forwarder.setRelayer(cfg.relayer, true);

        buyProcessor.grantRole(buyProcessor.FORWARDER_ROLE(), address(forwarder));
        sellProcessor.grantRole(sellProcessor.FORWARDER_ROLE(), address(forwarder));
        directBuyIssuer.grantRole(directBuyIssuer.FORWARDER_ROLE(), address(forwarder));

        /// ------------------ dividend distributor ------------------

        DividendDistribution dividendDistributor = new DividendDistribution(cfg.deployer);

        // add distributor
        dividendDistributor.grantRole(dividendDistributor.DISTRIBUTOR_ROLE(), cfg.distributor);

        vm.stopBroadcast();
    }
}
