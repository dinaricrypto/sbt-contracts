// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/orders/OrderProcessor.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Order is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);
        ERC20 usdc = ERC20(vm.envAddress("USDC"));
        OrderProcessor orderProcessor = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));

        console.log("User: %s", user);

        uint256 value = 2_000000;

        IOrderProcessor.Order memory order = IOrderProcessor.Order({
            requestTimestamp: 0,
            recipient: user,
            assetToken: 0xbEc8Aa74eBE96BffAb0b43D983ddcfbF54Ba0A04,
            paymentToken: address(usdc),
            sell: false,
            orderType: IOrderProcessor.OrderType.LIMIT,
            assetTokenQuantity: 0,
            paymentTokenQuantity: value,
            price: value,
            tif: IOrderProcessor.TIF.DAY
        });

        vm.startBroadcast(privateKey);

        usdc.approve(address(orderProcessor), value * 2);
        orderProcessor.createOrderStandardFees(order);

        vm.stopBroadcast();
    }
}
