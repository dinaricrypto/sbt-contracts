// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/orders/OrderProcessor.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Order is Script {
    function run() external {
        uint256 privateKey = vm.envUint("DEPLOY_KEY");
        address user = vm.addr(privateKey);
        OrderProcessor orderProcessor = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));
        ERC20 usdc = ERC20(vm.envAddress("USDC"));

        console.log("User: %s", user);

        uint256 value = 2_000000;

        IOrderProcessor.Order memory order = IOrderProcessor.Order({
            requestTimestamp: 0,
            recipient: user,
            assetToken: 0xFaD932bf52e386807B4C2B20A006AccF79e1E1D0,
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
