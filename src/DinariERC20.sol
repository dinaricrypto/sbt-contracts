// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solady/tokens/ERC20.sol";
import "solady/auth/OwnableRoles.sol";
import "./ITransferRestrictor.sol";

/// @notice ERC20 with minter and blacklist.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/DinariERC20.sol)
contract DinariERC20 is ERC20, OwnableRoles {
    event TransferRestrictorSet(ITransferRestrictor indexed transferRestrictor);

    string internal _name;
    string internal _symbol;

    /// @dev URI to information
    string public disclosures;
    ITransferRestrictor public transferRestrictor;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory disclosures_,
        ITransferRestrictor transferRestrictor_
    ) {
        _initializeOwner(msg.sender);

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

    function setTransferRestrictor(
        ITransferRestrictor restrictor
    ) external onlyOwner {
        transferRestrictor = restrictor;
        emit TransferRestrictorSet(restrictor);
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
        if (
            from == address(0) ||
            to == address(0) ||
            address(transferRestrictor) == address(0)
        ) {
            return;
        }

        transferRestrictor.requireNotRestricted(from, to);
    }
}
