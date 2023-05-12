// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Messager.sol";
import "../src/TransferRestrictor.sol";
import "../src/BridgedTokenFactory.sol";
import "../src/FlatOrderFees.sol";
import {SwapOrderIssuer} from "../src/SwapOrderIssuer.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

contract ErrorsScript is Script {
    event ErrorCode(bytes4 indexed code, string name);

    function run() external {
        vm.startBroadcast();

        emit ErrorCode(SwapOrderIssuer.ZeroValue.selector, "ZeroValue");
        emit ErrorCode(SwapOrderIssuer.ZeroValue.selector, "ZeroAddress");
        emit ErrorCode(SwapOrderIssuer.UnsupportedToken.selector, "UnsupportedToken");
        emit ErrorCode(SwapOrderIssuer.NotRecipient.selector, "NotRecipient");
        emit ErrorCode(SwapOrderIssuer.OrderNotFound.selector, "OrderNotFound");
        emit ErrorCode(SwapOrderIssuer.DuplicateOrder.selector, "DuplicateOrder");
        emit ErrorCode(SwapOrderIssuer.Paused.selector, "Paused");
        emit ErrorCode(SwapOrderIssuer.FillTooLarge.selector, "FillTooLarge");
        emit ErrorCode(SwapOrderIssuer.OrderTooSmall.selector, "OrderTooSmall");

        vm.stopBroadcast();
    }
}
