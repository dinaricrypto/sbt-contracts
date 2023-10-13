// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {dShare} from "./dShare.sol";

interface ITokenManager {
    /// @notice Check if token is current
    function isCurrentToken(address token) external view returns (bool);

    /// @notice Convert a token amount to current token after split
    /// @param token Token to convert
    /// @param amount Amount to convert
    /// @return currentToken Current token minted to user
    /// @return resultAmount Amount of current token minted to user
    /// @dev Accounts for multiple splits and returns the current token
    function convert(dShare token, uint256 amount) external returns (dShare currentToken, uint256 resultAmount);

    /// @notice Get the active token for any parent token
    /// @param token Token to get active token for
    function getCurrentToken(dShare token) external view returns (dShare);

    /**
     * @notice Retrieves the split information for a given token.
     * @param token The dShare token for which to retrieve split information.
     * @return newToken The new token created as a result of the split.
     * @return multiple The multiple at which the original token was split.
     * @return reverse Indicates whether the split was a reverse split.
     */
    function splits(dShare token) external view returns (dShare newToken, uint8 multiple, bool reverse);

    /// @notice Split a token
    /// @param token Token to split
    /// @param multiple Multiple to split by
    /// @param reverseSplit Whether to perform a reverse split
    /// @return newToken The new token created after the split
    /// @return aggregateSupply The aggregate supply after the split
    function split(dShare token, uint8 multiple, bool reverseSplit)
        external
        returns (dShare newToken, uint256 aggregateSupply);

    /// @notice Get the total aggregate supply after a split
    /// @param token Token to calculate supply expansion for
    /// @param multiple Multiple to split by
    /// @param reverseSplit Whether to perform a reverse split
    function getSupplyExpansion(dShare token, uint8 multiple, bool reverseSplit) external view returns (uint256);

    /// @notice Get the total aggregate balance of an account after a split
    /// @param token Token to calculate balance expansion for
    /// @param account Account to calculate balance for
    function getAggregateBalanceOf(dShare token, address account) external view returns (uint256 aggregateBalance);
}
