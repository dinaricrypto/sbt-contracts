// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {IdShare, ITransferRestrictor} from "./IdShare.sol";

import {ERC20Rebasing} from "./ERC20Rebasing.sol";

/// @notice Core token contract for bridged assets. Rebases on stock splits.
/// ERC20 with minter, burner, and blacklist
/// Uses solady ERC20 which allows EIP-2612 domain separator with `name` changes
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/dShare.sol)
contract dShare is IdShare, Initializable, ERC20Rebasing, AccessControlDefaultAdminRulesUpgradeable {
    /// ------------------ Types ------------------ ///

    error Unauthorized();
    error ZeroValue();

    /// @dev Emitted when `name` is set
    event NameSet(string name);
    /// @dev Emitted when `symbol` is set
    event SymbolSet(string symbol);
    /// @dev Emitted when transfer restrictor contract is set
    event TransferRestrictorSet(ITransferRestrictor indexed transferRestrictor);
    /// @dev Emitted when split factor is updated
    event BalancePerShareSet(uint256 balancePerShare);

    /// ------------------ Immutables ------------------ ///

    /// @notice Role for approved minters
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @notice Role for approved burners
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /// ------------------ State ------------------ ///

    struct dShareStorage {
        string _name;
        string _symbol;
        ITransferRestrictor _transferRestrictor;
        /// @dev Aggregate mult factor due to splits since deployment, ethers decimals
        uint128 _balancePerShare;
    }

    // keccak256(abi.encode(uint256(keccak256("dinaricrypto.storage.dShare")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant dShareStorageLocation = 0x7315beb2381679795e06870021c0fca5deb85616e29e098c2e7b7e488f185800;

    function _getdShareStorage() private pure returns (dShareStorage storage $) {
        assembly {
            $.slot := dShareStorageLocation
        }
    }

    /// ------------------ Initialization ------------------ ///

    function initialize(
        address owner,
        string memory _name,
        string memory _symbol,
        ITransferRestrictor _transferRestrictor
    ) public initializer {
        __AccessControlDefaultAdminRules_init_unchained(0, owner);

        dShareStorage storage $ = _getdShareStorage();
        $._name = _name;
        $._symbol = _symbol;
        $._transferRestrictor = _transferRestrictor;
        $._balancePerShare = _INITIAL_BALANCE_PER_SHARE;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// ------------------ Getters ------------------ ///

    /// @notice Token name
    function name() public view override returns (string memory) {
        dShareStorage storage $ = _getdShareStorage();
        return $._name;
    }

    /// @notice Token symbol
    function symbol() public view override returns (string memory) {
        dShareStorage storage $ = _getdShareStorage();
        return $._symbol;
    }

    /// @notice Contract to restrict transfers
    function transferRestrictor() public view returns (ITransferRestrictor) {
        dShareStorage storage $ = _getdShareStorage();
        return $._transferRestrictor;
    }

    function balancePerShare() public view override returns (uint128) {
        dShareStorage storage $ = _getdShareStorage();
        uint128 _balancePerShare = $._balancePerShare;
        // Override with default if not set due to upgrade
        if (_balancePerShare == 0) return _INITIAL_BALANCE_PER_SHARE;
        return _balancePerShare;
    }

    /// ------------------ Setters ------------------ ///

    /// @notice Set token name
    /// @dev Only callable by owner or deployer
    function setName(string calldata newName) external onlyRole(DEFAULT_ADMIN_ROLE) {
        dShareStorage storage $ = _getdShareStorage();
        $._name = newName;
        emit NameSet(newName);
    }

    /// @notice Set token symbol
    /// @dev Only callable by owner or deployer
    function setSymbol(string calldata newSymbol) external onlyRole(DEFAULT_ADMIN_ROLE) {
        dShareStorage storage $ = _getdShareStorage();
        $._symbol = newSymbol;
        emit SymbolSet(newSymbol);
    }

    /// @notice Update split factor
    /// @dev Relies on offchain computation of aggregate splits and reverse splits
    function setBalancePerShare(uint128 balancePerShare_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (balancePerShare_ == 0) revert ZeroValue();

        dShareStorage storage $ = _getdShareStorage();
        $._balancePerShare = balancePerShare_;
        emit BalancePerShareSet(balancePerShare_);
    }

    /// @notice Set transfer restrictor contract
    /// @dev Only callable by owner
    function setTransferRestrictor(ITransferRestrictor newRestrictor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        dShareStorage storage $ = _getdShareStorage();
        $._transferRestrictor = newRestrictor;
        emit TransferRestrictorSet(newRestrictor);
    }

    /// ------------------ Minting and Burning ------------------ ///

    /// @notice Mint tokens
    /// @param to Address to mint tokens to
    /// @param value Amount of tokens to mint
    /// @dev Only callable by approved minter
    function mint(address to, uint256 value) external onlyRole(MINTER_ROLE) {
        _mint(to, value);
    }

    /// @notice Burn tokens
    /// @param value Amount of tokens to burn
    /// @dev Only callable by approved burner
    function burn(uint256 value) external onlyRole(BURNER_ROLE) {
        _burn(msg.sender, value);
    }

    /// @notice Burn tokens from an account
    /// @param account Address to burn tokens from
    /// @param value Amount of tokens to burn
    /// @dev Only callable by approved burner
    function burnFrom(address account, uint256 value) external onlyRole(BURNER_ROLE) {
        _spendAllowance(account, msg.sender, value);
        _burn(account, value);
    }

    /// ------------------ Transfers ------------------ ///

    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        // If transferRestrictor is not set, no restrictions are applied
        dShareStorage storage $ = _getdShareStorage();
        ITransferRestrictor _transferRestrictor = $._transferRestrictor;
        if (address(_transferRestrictor) != address(0)) {
            // Check transfer restrictions
            _transferRestrictor.requireNotRestricted(from, to);
        }
    }

    /**
     * @param account The address of the account
     * @return Whether the account is blacklisted
     * @dev Returns true if the account is blacklisted , if the account is the zero address
     */
    function isBlacklisted(address account) external view returns (bool) {
        dShareStorage storage $ = _getdShareStorage();
        ITransferRestrictor _transferRestrictor = $._transferRestrictor;
        if (address(_transferRestrictor) == address(0)) return false;
        return _transferRestrictor.isBlacklisted(account);
    }
}
