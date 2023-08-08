// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {AccessControlDefaultAdminRules} from
    "openzeppelin-contracts/contracts/access/AccessControlDefaultAdminRules.sol";
import {ITransferRestrictor} from "./ITransferRestrictor.sol";

/// @notice Core token contract for bridged assets.
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/dShare.sol)
/// ERC20 with minter, burner, and blacklist
/// Uses solady ERC20 which allows EIP-2612 domain separator with `name` changes
contract dShare is ERC20, AccessControlDefaultAdminRules {
    /// ------------------ Types ------------------ ///

    error Unauthorized();
    error TokenSplit();

    /// @dev Emitted when `name` is set
    event NameSet(string name);
    /// @dev Emitted when `symbol` is set
    event SymbolSet(string symbol);
    /// @dev Emitted when `disclosures` URI is set
    event DisclosuresSet(string disclosures);
    /// @dev Emitted when transfer restrictor contract is set
    event TransferRestrictorSet(ITransferRestrictor indexed transferRestrictor);
    /// @dev Emitted when `split` is set
    event SplitSet();

    /// ------------------ Immutables ------------------ ///

    /// @notice Role for approved minters
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @notice Role for approved burners
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /// @notice Address of deployer
    /// @dev Has special mint and burn permissions
    address public immutable deployer;

    /// ------------------ State ------------------ ///

    /// @dev Token name
    string private _name;
    /// @dev Token symbol
    string private _symbol;

    /// @notice URI to disclosure information
    string public disclosures;
    /// @notice Contract to restrict transfers
    ITransferRestrictor public transferRestrictor;

    /// @notice Locks minting and burning after split
    bool public split;

    /// ------------------ Initialization ------------------ ///

    /// @notice Initialize token
    /// @param owner Owner of contract
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    /// @param disclosures_ URI to disclosure information
    /// @param transferRestrictor_ Contract to restrict transfers
    constructor(
        address owner,
        string memory name_,
        string memory symbol_,
        string memory disclosures_,
        ITransferRestrictor transferRestrictor_
    ) AccessControlDefaultAdminRules(0, owner) {
        deployer = msg.sender;
        _name = name_;
        _symbol = symbol_;
        disclosures = disclosures_;
        transferRestrictor = transferRestrictor_;
    }

    /// ------------------ Getters ------------------ ///

    /// @notice Returns the name of the token
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @notice Returns the symbol of the token
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// ------------------ Setters ------------------ ///

    /// @notice Set token name
    /// @dev Only callable by owner or deployer
    function setName(string calldata name_) external {
        if (msg.sender != deployer) {
            _checkRole(DEFAULT_ADMIN_ROLE);
        }
        _name = name_;
        emit NameSet(name_);
    }

    /// @notice Set token symbol
    /// @dev Only callable by owner or deployer
    function setSymbol(string calldata symbol_) external {
        if (msg.sender != deployer) {
            _checkRole(DEFAULT_ADMIN_ROLE);
        }
        _symbol = symbol_;
        emit SymbolSet(symbol_);
    }

    /// @notice Set disclosures URI
    /// @dev Only callable by owner
    function setDisclosures(string calldata disclosures_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        disclosures = disclosures_;
        emit DisclosuresSet(disclosures_);
    }

    /// @notice Set transfer restrictor contract
    /// @dev Only callable by owner
    function setTransferRestrictor(ITransferRestrictor restrictor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        transferRestrictor = restrictor;
        emit TransferRestrictorSet(restrictor);
    }

    /// @notice Set split lock
    /// @dev Only callable by deployer. Once set, cannot be unset.
    function setSplit() external {
        if (msg.sender != deployer) revert Unauthorized();

        split = true;

        emit SplitSet();
    }

    /// ------------------ Minting and Burning ------------------ ///

    /// @notice Mint tokens
    /// @param to Address to mint tokens to
    /// @param value Amount of tokens to mint
    /// @dev Only callable by approved minter and deployer
    /// @dev Not callable after split
    function mint(address to, uint256 value) external {
        if (split) {
            revert TokenSplit();
        } else if (msg.sender != deployer) {
            _checkRole(MINTER_ROLE);
        }

        _mint(to, value);
    }

    /// @notice Burn tokens
    /// @param value Amount of tokens to burn
    /// @dev Only callable by approved burner
    /// @dev Deployer can always burn after split
    function burn(uint256 value) external {
        if (!split) {
            _checkRole(BURNER_ROLE);
        } else if (msg.sender != deployer) {
            revert TokenSplit();
        }

        _burn(msg.sender, value);
    }

    /// ------------------ Transfers ------------------ ///

    /// @inheritdoc ERC20
    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        // Disallow transfers to the zero address
        if (to == address(0) && msg.sig != this.burn.selector) revert Unauthorized();

        // If transferRestrictor is not set, no restrictions are applied
        if (address(transferRestrictor) != address(0)) {
            // Check transfer restrictions
            transferRestrictor.requireNotRestricted(from, to);
        }
    }

    /**
     * @param account The address of the account
     * @return Whether the account is blacklisted
     * @dev Returns true if the account is blacklisted , if the account is the zero address
     */
    function isBlacklisted(address account) external view returns (bool) {
        if (address(transferRestrictor) == address(0)) return false;
        return transferRestrictor.isBlacklisted(account);
    }
}
