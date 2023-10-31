// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {dShare} from "./dShare.sol";

interface IdShareManager {
    /// @notice Check if token is current
    function isCurrentToken(address token) external view returns (bool);

    /// @notice Convert a token amount to current token after split
    /// @param token Token to convert
    /// @param amount Amount to convert
    /// @return currentToken Current token minted to user
    /// @return resultAmount Amount of current token minted to user
    /// @dev Accounts for multiple splits and returns the current token
    function convert(dShare token, uint256 amount) external returns (dShare currentToken, uint256 resultAmount);

    /// @notice Get first token in split chain
    /// @param token Token to get root parent for
    function getRootParent(dShare token) external view returns (dShare rootToken);

    function parentToken(dShare token) external view returns (dShare _parentToken);
}
