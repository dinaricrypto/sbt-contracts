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

        IVaultBridge.Order memory order = IVaultBridge.Order({
            user: vm.addr(deployerPrivateKey),
            assetToken: assetToken,
            paymentToken: paymentTokenAddress,
            sell: false,
            orderType: IVaultBridge.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 100,
            price: 10,
            tif: IVaultBridge.TIF.GTC
        });

        MockERC20 paymentToken = MockERC20(paymentTokenAddress);
        paymentToken.increaseAllowance(bridgeAddress, 100);

        VaultBridge bridge = VaultBridge(bridgeAddress);
        bridge.requestOrder(order, keccak256(abi.encode(block.number)));

        vm.stopBroadcast();
    }
}
