// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITokenLockCheck} from "./ITokenLockCheck.sol";
import {dShare} from "./dShare.sol";

interface IERC20Usdc {
    function isBlacklisted(address account) external view returns (bool);
}

interface IERC20Usdt {
    function isBlackListed(address account) external view returns (bool);
}

contract TokenLockCheck is ITokenLockCheck {
    address public immutable usdc;
    address public immutable usdt;

    constructor(address _usdc, address _usdt) {
        usdc = _usdc;
        usdt = _usdt;
    }

    function isTransferLocked(address token, address account) public view returns (bool) {
        if (token == usdc) {
            return IERC20Usdc(token).isBlacklisted(account);
        } else if (token == usdt) {
            return IERC20Usdt(token).isBlackListed(account);
        } else {
            return dShare(token).isBlacklisted(account);
        }
    }
}
