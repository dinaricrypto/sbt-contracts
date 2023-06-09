// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// solady ERC20 allows EIP-2612 domain separator with `name` changes
import {ERC20} from "solady/tokens/ERC20.sol";
import {AccessControlDefaultAdminRules} from
    "openzeppelin-contracts/contracts/access/AccessControlDefaultAdminRules.sol";
import {ITransferRestrictor} from "./ITransferRestrictor.sol";

/// @notice ERC20 with minter and blacklist.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/BridgedERC20.sol)
contract BridgedERC20 is ERC20, AccessControlDefaultAdminRules {
    event NameSet(string name);
    event SymbolSet(string symbol);
    event DisclosuresSet(string disclosures);
    event TransferRestrictorSet(ITransferRestrictor indexed transferRestrictor);

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    string internal _name;
    string internal _symbol;

    /// @dev URI to disclosure information
    string public disclosures;
    /// @dev Contract to restrict transfers
    ITransferRestrictor public transferRestrictor;

    constructor(
        address owner,
        string memory name_,
        string memory symbol_,
        string memory disclosures_,
        ITransferRestrictor transferRestrictor_
    ) AccessControlDefaultAdminRules(0, owner) {
        _name = name_;
        _symbol = symbol_;
        disclosures = disclosures_;
        transferRestrictor = transferRestrictor_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function setName(string calldata name_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _name = name_;
        emit NameSet(name_);
    }

    function setSymbol(string calldata symbol_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _symbol = symbol_;
        emit SymbolSet(symbol_);
    }

    function setDisclosures(string calldata disclosures_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        disclosures = disclosures_;
        emit DisclosuresSet(disclosures_);
    }

    function setTransferRestrictor(ITransferRestrictor restrictor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        transferRestrictor = restrictor;
        emit TransferRestrictorSet(restrictor);
    }

    /// @notice Mint tokens
    /// @param to Address to mint tokens to
    /// @param value Amount of tokens to mint
    /// @dev Only callable by approved minter
    function mint(address to, uint256 value) public virtual onlyRole(MINTER_ROLE) {
        _mint(to, value);
    }

    /// @notice Burn tokens
    /// @param value Amount of tokens to burn
    /// @dev Only callable by approved burner
    function burn(uint256 value) public virtual onlyRole(BURNER_ROLE) {
        _burn(msg.sender, value);
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal virtual override {
        // restrictions ignored for minting and burning
        if (from == address(0) || to == address(0) || address(transferRestrictor) == address(0)) {
            return;
        }

        transferRestrictor.requireNotRestricted(from, to);
    }
}
