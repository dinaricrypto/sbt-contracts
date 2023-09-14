// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {xERC4626, ERC4626} from "../../../src/xERC4626.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

contract MockxERC4626 is xERC4626 {
    ERC20 public immutable _asset;

    constructor(ERC20 _underlying, uint32 _rewardCycleLength) xERC4626(_rewardCycleLength) {
        _asset = _underlying;
    }

    function name() public view virtual override returns (string memory) {}

    function symbol() public view virtual override returns (string memory) {}

    function asset() public view virtual override returns (address) {
        return address(_asset);
    }
}
