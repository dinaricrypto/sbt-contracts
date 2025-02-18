// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {OracleLib} from "../src/common/OracleLib.sol";

contract OracleLibTest is Test {
    function testPairIndex() public {
        bytes32 pairIndex = OracleLib.pairIndex(address(0x1), address(0x2));
        assertEq(pairIndex, keccak256(abi.encodePacked(address(0x1), address(0x2))));
    }

    function testCalculatePriceOne(uint8 paymentTokenDecimals) public {
        vm.assume(paymentTokenDecimals <= 18);
        // 1:1 = 1e18
        uint256 price = OracleLib.calculatePrice(1e18, 10 ** paymentTokenDecimals, paymentTokenDecimals);
        assertEq(price, 1e18);
    }

    function testApplyPriceAssetToPaymentOne(uint8 paymentTokenDecimals) public {
        vm.assume(paymentTokenDecimals <= 18);
        uint256 payment = OracleLib.applyPriceAssetToPayment(1e18, 1e18, paymentTokenDecimals);
        assertEq(payment, 10 ** paymentTokenDecimals);
    }

    function testApplyPricePaymentToAssetOne(uint8 paymentTokenDecimals) public {
        vm.assume(paymentTokenDecimals <= 18);
        uint256 asset = OracleLib.applyPricePaymentToAsset(10 ** paymentTokenDecimals, 1e18, paymentTokenDecimals);
        assertEq(asset, 1e18);
    }
}
