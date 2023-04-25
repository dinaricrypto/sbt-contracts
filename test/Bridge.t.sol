// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Bridge.sol";
import "./mocks/MockBridgedERC20.sol";

contract BridgeTest is Test {
    event QuoteDurationSet(uint32 duration);
    event PaymentTokenEnabled(address indexed token, bool enabled);
    event PriceOracleEnabled(address indexed oracle, bool enabled);
    event PurchaseSubmitted(bytes32 indexed orderId, address indexed user, Bridge.OrderInfo orderInfo);
    event RedemptionSubmitted(bytes32 indexed orderId, address indexed user, Bridge.OrderInfo orderInfo);

    BridgedERC20 token;
    Bridge bridge;

    uint32 initialQuoteDuration = 5;

    function setUp() public {
        token = new MockBridgedERC20();
        bridge = new Bridge(initialQuoteDuration);
    }

    function testSetQuoteDuration(uint32 duration) public {
        vm.expectEmit(true, true, true, true);
        emit QuoteDurationSet(duration);
        bridge.setQuoteDuration(duration);
        assertEq(bridge.quoteDuration(), duration);
    } 

    function testSetPaymentTokenEnabled(address account, bool enabled) public {
        vm.expectEmit(true, true, true, true);
        emit PaymentTokenEnabled(account, enabled);
        bridge.setPaymentTokenEnabled(account, enabled);
        assertEq(bridge.paymentTokenEnabled(account), enabled);
    } 

    function testSetPriceOracleEnabled(address account, bool enabled) public {
        vm.expectEmit(true, true, true, true);
        emit PriceOracleEnabled(account, enabled);
        bridge.setPriceOracleEnabled(account, enabled);
        assertEq(bridge.priceOracleEnabled(account), enabled);
    } 
}
