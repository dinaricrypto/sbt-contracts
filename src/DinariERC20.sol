// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solady/tokens/ERC20.sol";

/// @notice ERC20 with minter and blacklist.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/DinariERC20.sol)
contract DinariERC20 is ERC20 {

    string internal _name;
    string internal _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }
}
