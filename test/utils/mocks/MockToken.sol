// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "solady/src/tokens/ERC20.sol";
import {AccessControl} from
    "openzeppelin-contracts/contracts/access/AccessControl.sol";

contract MockToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    string _name;
    string _symbol;

    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public isBlackListed;
    mapping(address => bool) public isBlocked;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address account, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(account, amount);
    }

    function blacklist(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        isBlacklisted[account] = true;
        isBlackListed[account] = true;
        isBlocked[account] = true;
    }
}
