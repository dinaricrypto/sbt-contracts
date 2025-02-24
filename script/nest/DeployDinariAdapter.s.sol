// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../../src/plume-nest/DinariAdapterToken.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployDinariAdapter is Script {
    function run() external {
        // load env variables
        uint256 deployKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployKey);
        address orderProcessor = vm.envAddress("ORDERPROCESSOR");
        address usdc = vm.envAddress("USDCE");
        address nestvault = vm.envAddress("NESTVAULT");

        address srlnd = 0x2D25006DC574ac902bCEeAE4F3Bb3FA6aa8780d6;
        address srlndw = 0x66A68a5A0B99B3E134E21f94e85a1361fDC4e438;

        console.log("deployer: %s", deployer);

        // send txs as deployer
        vm.startBroadcast(deployKey);

        DinariAdapterToken adapterImpl = new DinariAdapterToken();
        DinariAdapterToken adapter = DinariAdapterToken(
            address(
                new ERC1967Proxy(
                    address(adapterImpl),
                    abi.encodeCall(
                        DinariAdapterToken.initialize,
                        (deployer, "Nest SRLN.d", "nSRLN", usdc, srlnd, srlndw, nestvault, orderProcessor)
                    )
                )
            )
        );
        console.log("adapter: %s", address(adapter));

        vm.stopBroadcast();
    }
}
