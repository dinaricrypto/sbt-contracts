// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {xERC4626} from "./xERC4626.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IdShare} from "./IdShare.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract xdShare is Ownable, xERC4626 {
    ERC20 public underlyingToken;

    event ClaimeRewards(address indexed user, uint256 amount);
    event AccrueRewards(ERC20 dShare, address indexed user, uint256 rewardRounds);

    constructor(ERC20 token, uint32 _rewardsCycleLength) xERC4626(_rewardsCycleLength) {
        underlyingToken = token;
    }

    function name() public view virtual override returns (string memory) {
        return string.concat("Reinvesting ", underlyingToken.symbol());
    }

    function symbol() public view virtual override returns (string memory) {
        return string.concat(underlyingToken.symbol(), ".x");
    }

    function asset() public view virtual override returns (address) {
        return address(underlyingToken);
    }
}
