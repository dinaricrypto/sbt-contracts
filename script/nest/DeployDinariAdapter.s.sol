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
        address usdc = vm.envAddress("USDC");

        address amznd = 0x6Ca703338bcBF73Ad48c1Cc33Ab2D0706bC90AB3;
        address amzndw = 0xfa8287826C1381289d6079DB12cDf402E3F80f73;

        console.log("deployer: %s", deployer);

        bytes32 salt = keccak256(abi.encodePacked("0.4.3-test"));

        // send txs as deployer
        vm.startBroadcast(deployKey);

        DinariAdapterToken adapterImpl = new DinariAdapterToken{salt: salt}();
        DinariAdapterToken adapter = DinariAdapterToken(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(adapterImpl),
                    abi.encodeCall(
                        DinariAdapterToken.initialize,
                        (deployer, "AMZN.d Nest Adapter", "AMZN.dn", usdc, amznd, amzndw, deployer, orderProcessor)
                    )
                )
            )
        );
        console.log("adapter: %s", address(adapter));

        vm.stopBroadcast();
    }
}
