// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

// solady ERC20 allows EIP-2612 domain separator with `name` changes
import "solady/tokens/ERC20.sol";
import "openzeppelin/access/Ownable2Step.sol";
import "./ITransferRestrictor.sol";

/// @notice ERC20 with minter and blacklist.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/BridgedERC20.sol)
contract BridgedERC20 is ERC20, Ownable2Step {
    error Unauthorized();

    event MinterSet(address indexed account, bool enabled);
    event NameSet(string name);
    event SymbolSet(string symbol);
    event DisclosuresSet(string disclosures);
    event TransferRestrictorSet(ITransferRestrictor indexed transferRestrictor);

    string internal _name;
    string internal _symbol;

    mapping(address => bool) public isMinter;

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
        _transferOwnership(owner);

        _name = name_;
        _symbol = symbol_;
        disclosures = disclosures_;
        transferRestrictor = transferRestrictor_;
    }

    modifier onlyMinter() {
        if (!isMinter[msg.sender]) revert Unauthorized();
        _;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function setMinter(address minter, bool enabled) external onlyOwner {
        isMinter[minter] = enabled;
        emit MinterSet(minter, enabled);
    }

    function setName(string calldata name_) external onlyOwner {
        _name = name_;
        emit NameSet(name_);
    }

    function setSymbol(string calldata symbol_) external onlyOwner {
        _symbol = symbol_;
        emit SymbolSet(symbol_);
    }

    function setDisclosures(string calldata disclosures_) external onlyOwner {
        disclosures = disclosures_;
        emit DisclosuresSet(disclosures_);
    }

    function setTransferRestrictor(ITransferRestrictor restrictor) external onlyOwner {
        transferRestrictor = restrictor;
        emit TransferRestrictorSet(restrictor);
    }

    function mint(address to, uint256 value) public virtual onlyMinter {
        _mint(to, value);
    }

    function burn(uint256 value) public virtual onlyMinter {
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
