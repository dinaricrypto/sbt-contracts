// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITokenLockCheck} from "./ITokenLockCheck.sol";
import {dShare} from "./dShare.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

interface IERC20Usdt {
    function isBlackListed(address account) external view returns (bool);
}

contract TokenLockCheck is ITokenLockCheck, Ownable {
    using Address for address;

    error NotContract();

    mapping(address => bytes4) public callSelector;

    constructor(address _usdt) {
        // usdc is same as dShare
        callSelector[_usdt] = IERC20Usdt.isBlackListed.selector;
    }

    function setCallSelector(address token, bytes4 selector) external onlyOwner {
        if (token.isContract()) revert NotContract();

        callSelector[token] = selector;
    }

    function isTransferLocked(address token, address account) public view returns (bool) {
        bytes4 selector = callSelector[token];
        // default to dShare.isBlacklisted
        if (selector == 0) selector = dShare.isBlacklisted.selector;

        return abi.decode(
            token.functionStaticCall(
                abi.encodeWithSelector(selector, account), "TokenLockCheck: low-level static call failed"
            ),
            (bool)
        );
    }
}
