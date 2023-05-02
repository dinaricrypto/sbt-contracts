// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/VaultBridge.sol";
import "solady-test/utils/mocks/MockERC20.sol";

contract DummyOrderScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address bridgeAddress = vm.envAddress("VAULT_BRIDGE");
        address assetToken = vm.envAddress("ASSET_TOKEN");
        address paymentTokenAddress = vm.envAddress("PAYMENT_TOKEN");
        vm.startBroadcast(deployerPrivateKey);

        VaultBridge.Swap memory swap = VaultBridge.Swap({
            user: vm.addr(deployerPrivateKey),
            assetToken: assetToken,
            paymentToken: paymentTokenAddress,
            sell: false,
            amount: 100
        });

        MockERC20 paymentToken = MockERC20(paymentTokenAddress);
        paymentToken.increaseAllowance(bridgeAddress, swap.amount);

        VaultBridge bridge = VaultBridge(bridgeAddress);
        bridge.submitSwap(swap, keccak256(abi.encode(block.number)));

        vm.stopBroadcast();
    }
}
