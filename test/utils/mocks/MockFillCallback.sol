// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IOrderFillCallback, IERC165} from "../../../src/orders/IOrderFillCallback.sol";
import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

contract MockFillCallback is IOrderFillCallback, ERC165 {
    bytes4 public constant MAGIC_VALUE = this.onOrderFill.selector;

    bytes4 public magicValue = MAGIC_VALUE;

    function onOrderFill(
        uint256 id,
        address paymentToken,
        address assetToken,
        uint256 assetAmount,
        uint256 paymentAmount,
        bool sell
    ) external view override returns (bytes4) {
        return magicValue;
    }

    function setMagicValue(bytes4 _magicValue) external {
        magicValue = _magicValue;
    }

    function call(address target, bytes memory data) external returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call(data);
        require(success, "MockFillCallback: call failed");
        return returndata;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IOrderFillCallback).interfaceId || super.supportsInterface(interfaceId);
    }
}
