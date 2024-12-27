// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/orders/OrderProcessor.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Order is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);
        OrderProcessor orderProcessor = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));
        ERC20 usdc = ERC20(vm.envAddress("USDCE"));

        console.log("User: %s", user);

        uint256 value = 2_000_000;

        IOrderProcessor.Order memory order = IOrderProcessor.Order({
            requestTimestamp: 0,
            recipient: user,
            assetToken: 0x2D25006DC574ac902bCEeAE4F3Bb3FA6aa8780d6,
            paymentToken: address(usdc),
            sell: false,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: value,
            price: 0,
            tif: IOrderProcessor.TIF.DAY
        });

        vm.startBroadcast(privateKey);

        usdc.approve(address(orderProcessor), value * 2);
        orderProcessor.createOrderStandardFees(order);

        vm.stopBroadcast();
    }
}
