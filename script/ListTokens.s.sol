// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/DShareFactory.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

contract ListTokens is Script {
    // When new issuers have been deployed, this script will add tokens to them.
    function run() external {
        DShareFactory factory = DShareFactory(vm.envAddress("DSHAREFACTORY"));

        (address[] memory dshares, address[] memory wrappeddshares) = factory.getDShares();
        for (uint256 i = 0; i < dshares.length; i++) {
            console.log("%s: %s", ERC20(dshares[i]).symbol(), dshares[i]);
            console.log("%s: %s", ERC20(wrappeddshares[i]).symbol(), wrappeddshares[i]);
        }
    }
}
