// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {EnumerableMap} from "openzeppelin-contracts/contracts/utils/structs/EnumerableMap.sol";

/// @notice Livrary for EnumerableMaps with Uint value types
library EnumerableMapMath {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    // TODO: using EnumerableMap for EnumerableMap.UintToUintMap;
    // TODO: using EnumerableMap for EnumerableMap.Bytes32ToUintMap;

    function increment(EnumerableMap.AddressToUintMap storage map, address key, uint256 value) internal {
        if (map.contains(key)) {
            map.set(key, map.get(key) + value);
        } else {
            map.set(key, value);
        }
    }

    function decrement(EnumerableMap.AddressToUintMap storage map, address key, uint256 value) internal {
        uint256 newValue = map.get(key) - value;
        if (newValue == 0) {
            map.remove(key);
        } else {
            map.set(key, newValue);
        }
    }
}
