// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// import "solady/src/tokens/ERC20.sol";
import {ERC20PermitVersion} from "./ERC20PermitVersion.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20PermitVersion, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    string _name;
    string _symbol;
    string _version;

    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public isBlackListed;
    mapping(address => bool) public isBlocked;

    constructor(string memory name_, string memory symbol_, string memory version_)
        ERC20PermitVersion(name_, version_)
        ERC20(name_, symbol_)
    {
        _name = name_;
        _symbol = symbol_;
        _version = version_;
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

    function version() public view returns (string memory) {
        return _version;
    }

    function blacklist(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        isBlacklisted[account] = true;
        isBlackListed[account] = true;
        isBlocked[account] = true;
    }
}
