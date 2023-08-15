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

    constructor(address usdc, address usdt) {
        // usdc is same as dShare
        callSelector[usdc] = dShare.isBlacklisted.selector;
        callSelector[usdt] = IERC20Usdt.isBlackListed.selector;
    }

    function setCallSelector(address token, bytes4 selector) external onlyOwner {
        // if token is a contract, it must implement the selector
        _checkTransferLocked(token, address(this), selector);

        callSelector[token] = selector;
    }

    function setAsDShare(address token) external onlyOwner {
        // if token is a contract, it must implement the selector
        _checkTransferLocked(token, address(this), dShare.isBlacklisted.selector);

        callSelector[token] = dShare.isBlacklisted.selector;
    }

    function _checkTransferLocked(address token, address account, bytes4 selector) internal view returns (bool) {
        // assumes bool result
        return abi.decode(
            token.functionStaticCall(
                abi.encodeWithSelector(selector, account), "TokenLockCheck: low-level static call failed"
            ),
            (bool)
        );    }

    function isTransferLocked(address token, address account) external view returns (bool) {
        bytes4 selector = callSelector[token];
        // if no selector is set, default to locked == false
        if (selector == 0) return false;

        return _checkTransferLocked(token, account, selector);
    }
}
