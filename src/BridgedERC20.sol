// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "solady/tokens/ERC20.sol";
import "solady/utils/Multicallable.sol";
import "solady/auth/OwnableRoles.sol";
import "./ITransferRestrictor.sol";

/// @notice ERC20 with minter and blacklist.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/BridgedERC20.sol)
contract BridgedERC20 is ERC20, Multicallable, OwnableRoles {
    // TODO: compare with openeden vault
    event NameSet(string name);
    event SymbolSet(string symbol);
    event DisclosuresSet(string disclosures);
    event TransferRestrictorSet(ITransferRestrictor indexed transferRestrictor);

    string internal _name;
    string internal _symbol;

    /// @dev URI to information
    string public disclosures;
    ITransferRestrictor public transferRestrictor;

    constructor(
        address owner,
        string memory name_,
        string memory symbol_,
        string memory disclosures_,
        ITransferRestrictor transferRestrictor_
    ) {
        _initializeOwner(owner);

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

    function minterRole() external pure returns (uint256) {
        return _ROLE_1;
    }

    function setName(string calldata name_) external {
        _name = name_;
        emit NameSet(name_);
    }

    function setSymbol(string calldata symbol_) external {
        _symbol = symbol_;
        emit SymbolSet(symbol_);
    }

    function setDisclosures(string calldata disclosures_) external {
        disclosures = disclosures_;
        emit DisclosuresSet(disclosures_);
    }

    function setTransferRestrictor(ITransferRestrictor restrictor) external onlyOwner {
        transferRestrictor = restrictor;
        emit TransferRestrictorSet(restrictor);
    }

    function mint(address to, uint256 value) public virtual onlyRoles(_ROLE_1) {
        _mint(to, value);
    }

    function burn(uint256 value) public virtual onlyRoles(_ROLE_1) {
        _burn(msg.sender, value);
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal virtual override {
        /* _mint() or _burn() will set one of to address(0)
         *  no need to limit for these scenarios
         */
        if (from == address(0) || to == address(0) || address(transferRestrictor) == address(0)) {
            return;
        }

        transferRestrictor.requireNotRestricted(from, to);
    }
}
