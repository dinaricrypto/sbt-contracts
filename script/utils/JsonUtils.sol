// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {VmSafe} from "forge-std/Vm.sol";

library JsonUtils {
    function getAddressFromJson(VmSafe vm, string memory json, string memory selector)
        external
        pure
        returns (address)
    {
        try vm.parseJsonAddress(json, selector) returns (address addr) {
            return addr;
        } catch {
            revert(string.concat("Missing or invalid address at path: ", selector));
        }
    }

    function getBoolFromJson(VmSafe vm, string memory json, string memory selector) external pure returns (bool) {
        try vm.parseJsonBool(json, selector) returns (bool value) {
            return value;
        } catch {
            revert(string.concat("Missing or invalid boolean at path: ", selector));
        }
    }
}
