// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITransferRestrictor} from "./ITransferRestrictor.sol";

interface IBridgedERC20Factory {
    function createBridgedERC20(
        address owner,
        string memory name,
        string memory symbol,
        string memory disclosures,
        ITransferRestrictor transferRestrictor,
        uint256 splitRatio,
        bool reverseSplit,
        address factory
    ) external returns (address);
}
