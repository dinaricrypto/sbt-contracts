// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IOrderFillCallback, IERC165} from "../../../src/orders/IOrderFillCallback.sol";
import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

contract MockFillCallback is IOrderFillCallback, ERC165 {
    function onOrderFill(
        uint256 id,
        address paymentToken,
        address assetToken,
        uint256 assetAmount,
        uint256 paymentAmount,
        bool sell
    ) external pure override returns (bytes4) {
        return this.onOrderFill.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IOrderFillCallback).interfaceId || super.supportsInterface(interfaceId);
    }
}
