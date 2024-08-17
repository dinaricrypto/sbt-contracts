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

        console.log("User: %s", user);

        ERC20 usdc = ERC20(0x709CE4CB4b6c2A03a4f938bA8D198910E44c11ff);
        uint256 value = 216676000;

        IOrderProcessor.Order memory order = IOrderProcessor.Order({
            requestTimestamp: 0,
            recipient: user,
            assetToken: 0xD771a71E5bb303da787b4ba2ce559e39dc6eD85c,
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
