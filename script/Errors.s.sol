// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Messager.sol";
import "../src/TransferRestrictor.sol";
import "../src/BridgedTokenFactory.sol";
import "../src/FlatOrderFees.sol";
import {LimitOrderBridge} from "../src/LimitOrderBridge.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

contract ErrorsScript is Script {
    event ErrorCode(bytes4 indexed code, string name);

    function run() external {
        vm.startBroadcast();

        emit ErrorCode(LimitOrderBridge.ZeroValue.selector, "ZeroValue");
        emit ErrorCode(LimitOrderBridge.ZeroValue.selector, "ZeroAddress");
        emit ErrorCode(LimitOrderBridge.UnsupportedPaymentToken.selector, "UnsupportedPaymentToken");
        emit ErrorCode(LimitOrderBridge.NotRecipient.selector, "NotRecipient");
        emit ErrorCode(LimitOrderBridge.OnlyLimitOrders.selector, "OnlyLimitOrders");
        emit ErrorCode(LimitOrderBridge.OrderNotFound.selector, "OrderNotFound");
        emit ErrorCode(LimitOrderBridge.DuplicateOrder.selector, "DuplicateOrder");
        emit ErrorCode(LimitOrderBridge.Paused.selector, "Paused");
        emit ErrorCode(LimitOrderBridge.FillTooLarge.selector, "FillTooLarge");
        emit ErrorCode(LimitOrderBridge.NotBuyOrder.selector, "NotBuyOrder");
        emit ErrorCode(LimitOrderBridge.OrderTooSmall.selector, "OrderTooSmall");

        vm.stopBroadcast();
    }
}
