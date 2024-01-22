// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {TransferRestrictor} from "../src/TransferRestrictor.sol";
import {DShareFactory} from "../src/DShareFactory.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployFactory is Script {
    struct DeployConfig {
        address deployer;
        address transferRestrictor;
        address dSharesBeacon;
        address wrappedDSharesBeacon;
    }

    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        DeployConfig memory cfg = DeployConfig({
            deployer: vm.addr(deployerPrivateKey),
            transferRestrictor: vm.envAddress("TRANSFER_RESTRICTOR"),
            dSharesBeacon: vm.envAddress("DSHARE_BEACON"),
            wrappedDSharesBeacon: vm.envAddress("WRAPPEDDSHARE_BEACON")
        });

        console.log("deployer: %s", cfg.deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        /// ------------------ factory ------------------

        DShareFactory dShareFactoryImpl = new DShareFactory();
        new ERC1967Proxy(
            address(dShareFactoryImpl),
            abi.encodeCall(
                DShareFactory.initialize,
                (
                    cfg.deployer,
                    UpgradeableBeacon(cfg.dSharesBeacon),
                    UpgradeableBeacon(cfg.wrappedDSharesBeacon),
                    TransferRestrictor(cfg.transferRestrictor)
                )
            )
        );

        vm.stopBroadcast();
    }
}
