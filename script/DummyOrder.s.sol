// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/SwapOrderIssuer.sol";
import "solady-test/utils/mocks/MockERC20.sol";

contract DummyOrderScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address bridgeAddress = vm.envAddress("VAULT_BRIDGE");
        address assetToken = vm.envAddress("ASSET_TOKEN");
        address paymentTokenAddress = vm.envAddress("PAYMENT_TOKEN");
        vm.startBroadcast(deployerPrivateKey);

        SwapOrderIssuer.SwapOrder memory order = SwapOrderIssuer.SwapOrder({
            recipient: vm.addr(deployerPrivateKey),
            assetToken: assetToken,
            paymentToken: paymentTokenAddress,
            sell: false,
            quantityIn: 100
        });

        // increase payment token allowance for bridge
        MockERC20 paymentToken = MockERC20(paymentTokenAddress);
        paymentToken.increaseAllowance(bridgeAddress, 100);

        // request order
        SwapOrderIssuer issuer = SwapOrderIssuer(bridgeAddress);
        issuer.requestOrder(order, keccak256(abi.encode(block.number)));

        vm.stopBroadcast();
    }
}
