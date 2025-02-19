// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

library OrderErrors {
    /// @dev Signature deadline expired
    error ExpiredSignature();
    /// @dev Zero address
    error ZeroAddress();
    /// @dev Orders are paused
    error Paused();
    /// @dev Zero value
    error ZeroValue();
    error OrderNotActive();
    error ExistingOrder();
    /// @dev Amount too large
    error AmountTooLarge();
    error UnsupportedToken(address token);
    /// @dev blacklist address
    error Blacklist();
    /// @dev Thrown when assetTokenQuantity's precision doesn't match the expected precision in orderDecimals.
    error InvalidPrecision();
    error LimitPriceNotSet();
    error OrderFillBelowLimitPrice();
    error OrderFillAboveLimitPrice();
    error NotOperator();
    error NotRequester();
}
