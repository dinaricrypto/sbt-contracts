// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {EscrowOrderProcessor} from "../src/orders/EscrowOrderProcessor.sol";
import {BuyUnlockedProcessor} from "../src/orders/BuyUnlockedProcessor.sol";
import {TokenLockCheck, ITokenLockCheck, IERC20Usdc} from "../src/TokenLockCheck.sol";
import {Forwarder} from "../src/forwarder/Forwarder.sol";
import {DividendDistribution} from "../src/dividend/DividendDistribution.sol";

contract DeployForwarderScript is Script {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
        EscrowOrderProcessor orderProcessor = EscrowOrderProcessor(vm.envAddress("ISSUER"));
        BuyUnlockedProcessor directBuyProcessor = BuyUnlockedProcessor(vm.envAddress("DIRECT_ISSUER"));
        address relayer = vm.envAddress("RELAYER");
        address usdc = vm.envAddress("USDC");
        address usdce = vm.envAddress("USDCE");
        address usdt = vm.envAddress("USDT");
        address ethusdoracle = vm.envAddress("ETHUSDORACLE");
        address usdcoracle = vm.envAddress("USDCORACLE");

        console.log("deployer: %s", vm.addr(deployerPrivateKey));

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        Forwarder forwarder = new Forwarder(ethusdoracle);
        forwarder.setFeeBps(2000);

        forwarder.setPaymentOracle(usdc, usdcoracle);
        forwarder.setPaymentOracle(usdce, usdcoracle);
        forwarder.setPaymentOracle(usdt, usdcoracle);

        forwarder.setSupportedModule(address(orderProcessor), true);
        forwarder.setSupportedModule(address(directBuyProcessor), true);

        forwarder.setRelayer(relayer, true);

        orderProcessor.grantRole(orderProcessor.FORWARDER_ROLE(), address(forwarder));
        directBuyProcessor.grantRole(directBuyProcessor.FORWARDER_ROLE(), address(forwarder));

        vm.stopBroadcast();
    }
}
