// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITransferRestrictor} from "../ITransferRestrictor.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {AccessControlDefaultAdminRules} from
    "openzeppelin-contracts/contracts/access/AccessControlDefaultAdminRules.sol";

/// @notice Core token contract for bridged assets.
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/dShare.sol)
contract USDd is ERC20, AccessControlDefaultAdminRules {
    // TODO: upgradeable?

    /// ------------------ Types ------------------ ///

    error Unauthorized();

    /// @dev Emitted when transfer restrictor contract is set
    event TransferRestrictorSet(ITransferRestrictor indexed transferRestrictor);

    /// ------------------ Immutables ------------------ ///

    /// @notice Role for approved minters
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @notice Role for approved burners
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /// ------------------ State ------------------ ///

    /// @notice Contract to restrict transfers
    ITransferRestrictor public transferRestrictor;

    /// ------------------ Initialization ------------------ ///

    /// @notice Initialize token
    /// @param owner Owner of contract
    /// @param transferRestrictor_ Contract to restrict transfers
    constructor(address owner, ITransferRestrictor transferRestrictor_) AccessControlDefaultAdminRules(0, owner) {
        transferRestrictor = transferRestrictor_;
    }

    /// @notice Returns the name of the token
    function name() public pure override returns (string memory) {
        return "Dinari USD";
    }

    /// @notice Returns the symbol of the token
    function symbol() public pure override returns (string memory) {
        return "USD.d";
    }

    /// ------------------ Admin ------------------ ///

    /// @notice Set transfer restrictor contract
    /// @dev Only callable by owner
    function setTransferRestrictor(ITransferRestrictor restrictor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        transferRestrictor = restrictor;
        emit TransferRestrictorSet(restrictor);
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
