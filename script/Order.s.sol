// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OrderProcessor, IOrderProcessor} from "../src/orders/OrderProcessor.sol";

contract Order is Script {
    using SafeERC20 for IERC20;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("USER_KEY");
        OrderProcessor issuer = OrderProcessor(vm.envAddress("ISSUER"));

        vm.startBroadcast(deployerPrivateKey);

        IOrderProcessor.Order memory order = IOrderProcessor.Order(
            0xAdFeB630a6aaFf7161E200088B02Cf41112f8B98,
            0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7,
            0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
            true,
            IOrderProcessor.OrderType.MARKET,
            12000000000000000,
            0,
            0,
            IOrderProcessor.TIF.GTC,
            address(0),
            0
        );
        // IERC20(order.assetToken).safeIncreaseAllowance(address(issuer), order.assetTokenQuantity);
        issuer.requestOrder(order);

        vm.stopBroadcast();
    }
}
