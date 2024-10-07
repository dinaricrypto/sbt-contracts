// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

/// @notice A standard callback for order fills
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/orders/IOrderFillCallback.sol)
/// @dev OrderProcessor will call this function on the order requester after a fill
interface IOrderFillCallback is IERC165 {
    /// @notice Callback for order fills
    /// @param id Order ID
    /// @param paymentToken Payment token address
    /// @param assetToken Asset token address
    /// @param assetAmount Amount of asset token filled
    /// @param paymentAmount Amount of payment token filled
    /// @param sell True if the order is a sell order
    /// @return 0x2f551a13 = `bytes4(keccak256("onOrderFill(uint256,address,address,uint256,uint256,bool)"))` unless throwing
    function onOrderFill(
        uint256 id,
        address paymentToken,
        address assetToken,
        uint256 assetAmount,
        uint256 paymentAmount,
        bool sell
    ) external returns (bytes4);
}
