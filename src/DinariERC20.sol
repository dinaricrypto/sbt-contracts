// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solady/tokens/ERC20.sol";
import "solady/auth/OwnableRoles.sol";
import "./IKycManager.sol";

/// @notice ERC20 with minter and blacklist.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/DinariERC20.sol)
contract DinariERC20 is ERC20, OwnableRoles {
    string internal _name;
    string internal _symbol;

    IKycManager internal _kycManager;

    constructor(
        string memory name_,
        string memory symbol_,
        IKycManager kycManager_
    ) {
        _name = name_;
        _symbol = symbol_;
        _kycManager = kycManager_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function minterRole() external pure returns (uint256) {
        return _ROLE_1;
    }

    function mint(address to, uint256 value) public virtual onlyRoles(_ROLE_1) {
        _mint(to, value);
    }

    function burn(
        address from,
        uint256 value
    ) public virtual onlyRoles(_ROLE_1) {
        _burn(from, value);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal virtual override {
        /* _mint() or _burn() will set one of to address(0)
         *  no need to limit for these scenarios
         */
        if (from == address(0) || to == address(0)) {
            return;
        }

        _kycManager.onlyNotBanned(from);
        _kycManager.onlyNotBanned(to);

        if (_kycManager.isStrict()) {
            _kycManager.onlyKyc(from);
            _kycManager.onlyKyc(to);
        } else if (_kycManager.isUSKyc(from)) {
            _kycManager.onlyKyc(to);
        }
    }
}
