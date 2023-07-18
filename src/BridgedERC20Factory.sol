// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IBridgedERC20Factory, ITransferRestrictor} from "./IBridgedERC20Factory.sol";
import {BridgedERC20} from "./BridgedERC20.sol";

contract BridgedERC20Factory is IBridgedERC20Factory {
    function createBridgedERC20(
        address owner,
        string memory name,
        string memory symbol,
        string memory disclosures,
        ITransferRestrictor transferRestrictor,
        uint8 splitMultiple,
        bool reverseSplit,
        address factory
    ) external returns (address) {
        return address(
            new BridgedERC20(
                    owner,
                    name,
                    symbol,
                    disclosures,
                    transferRestrictor,
                    splitMultiple,
                    reverseSplit,
                    factory
                )
        );
    }
}
