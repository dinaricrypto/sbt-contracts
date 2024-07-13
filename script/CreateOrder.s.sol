// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "../src/orders/OrderProcessor.sol";

contract CreateOrder is Script {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        OrderProcessor orderProcessor = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));
        address usdc = vm.envAddress("USDC");

        IOrderProcessor.Order memory order = IOrderProcessor.Order({
            recipient: deployer,
            assetToken: 0x930E85C59B257fc48997B3F597a92b3CAef2bFB4, // MSFT
            paymentToken: usdc,
            sell: false,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: 1_000_000,
            price: 0,
            tif: IOrderProcessor.TIF.GTC,
            splitRecipient: address(0),
            splitAmount: 0
        });

        console.log("account: %s", deployer);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        // approve
        IERC20(usdc).approve(address(orderProcessor), 1_000_000 + order.paymentTokenQuantity * 2);

        // create order
        orderProcessor.requestOrder(order);

        vm.stopBroadcast();
    }
}
