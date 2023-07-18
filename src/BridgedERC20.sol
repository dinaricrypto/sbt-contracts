// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {AccessControlDefaultAdminRules} from
    "openzeppelin-contracts/contracts/access/AccessControlDefaultAdminRules.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {ITransferRestrictor} from "./ITransferRestrictor.sol";
import {IBridgedERC20Factory} from "./IBridgedERC20Factory.sol";

/// @notice Core token contract for bridged assets.
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/BridgedERC20.sol)
/// ERC20 with minter, burner, blacklist, and managed split
/// Uses solady ERC20 which allows EIP-2612 domain separator with `name` changes
contract BridgedERC20 is ERC20, AccessControlDefaultAdminRules {
    using Address for address;

    /// ------------------ Types ------------------ ///

    /// @dev Emitted when `name` is set
    event NameSet(string name);
    /// @dev Emitted when `symbol` is set
    event SymbolSet(string symbol);
    /// @dev Emitted when `disclosures` URI is set
    event DisclosuresSet(string disclosures);
    /// @dev Emitted when transfer restrictor contract is set
    event TransferRestrictorSet(ITransferRestrictor indexed transferRestrictor);
    /// @dev Emitted when a split is performed
    event Split(BridgedERC20 newToken, uint8 splitMultiple, bool reverseSplit, string legacyName, string legacySymbol);

    error UnauthorizedOperation();
    error TokenSplit();
    error ZeroMultiple();

    /// ------------------ Immutables ------------------ ///

    /// @notice Role for approved minters
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @notice Role for approved burners
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /// @notice Address of pre-split token or first deployer
    address public immutable deployer;
    /// @notice Ratio of legacy token to new token
    uint8 public immutable splitMultiple;
    /// @notice True if this is a reverse split
    bool public immutable reverseSplit;
    /// @notice Factory contract to create new tokens
    address public immutable factory;

    /// ------------------ State ------------------ ///

    /// @dev Token name
    string private _name;
    /// @dev Token symbol
    string private _symbol;

    /// @notice URI to disclosure information
    string public disclosures;
    /// @notice Contract to restrict transfers
    ITransferRestrictor public transferRestrictor;

    /// @notice Address of post-split token
    BridgedERC20 public childToken;

    /// ------------------ Initialization ------------------ ///

    /// @notice Initialize token
    /// @param owner Owner of contract
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    /// @param disclosures_ URI to disclosure information
    /// @param transferRestrictor_ Contract to restrict transfers
    /// @param splitMultiple_ Ratio of legacy token to new token
    /// @param reverseSplit_ True if this is a reverse split
    /// @param factory_ Factory contract to create new tokens
    constructor(
        address owner,
        string memory name_,
        string memory symbol_,
        string memory disclosures_,
        ITransferRestrictor transferRestrictor_,
        uint8 splitMultiple_,
        bool reverseSplit_,
        address factory_
    ) AccessControlDefaultAdminRules(0, owner) {
        _name = name_;
        _symbol = symbol_;
        disclosures = disclosures_;
        transferRestrictor = transferRestrictor_;
        deployer = msg.sender;
        splitMultiple = splitMultiple_;
        reverseSplit = reverseSplit_;
        factory = factory_;
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
    /// @dev Only callable by owner
    function setName(string calldata name_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _name = name_;
        emit NameSet(name_);
    }

    /// @notice Set token symbol
    /// @dev Only callable by owner
    function setSymbol(string calldata symbol_) public onlyRole(DEFAULT_ADMIN_ROLE) {
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

    /// ------------------ Minting and Burning ------------------ ///

    /// @notice Mint tokens
    /// @param to Address to mint tokens to
    /// @param value Amount of tokens to mint
    /// @dev Only callable by approved minter until split
    function mint(address to, uint256 value) external onlyRole(MINTER_ROLE) {
        if (address(childToken) != address(0)) revert TokenSplit();

        _mint(to, value);
    }

    /// @notice Burn tokens
    /// @param value Amount of tokens to burn
    /// @dev Only callable by approved burner
    /// @dev Only callable by child token after split
    function burn(uint256 value) external {
        address _childToken = address(childToken);
        if (_childToken != address(0)) {
            if (msg.sender != _childToken) revert TokenSplit();
        } else {
            _checkRole(BURNER_ROLE);
        }

        _burn(msg.sender, value);
    }

    /// ------------------ Transfers ------------------ ///

    /// @inheritdoc ERC20
    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        // Restrictions ignored for minting and burning
        // If transferRestrictor is not set, no restrictions are applied
        if (from == address(0) || address(transferRestrictor) == address(0)) {
            return;
        }
        if (to == address(0) && msg.sig != this.burn.selector) revert UnauthorizedOperation();

        // Check transfer restrictions
        transferRestrictor.requireNotRestricted(from, to);
    }

    /**
     * @param account The address of the account
     * @return Whether the account is blacklisted
     * @dev Returns true if the account is blacklisted , if the account is the zero address
     */
    function isBlacklisted(address account) external view returns (bool) {
        if (account == address(0)) return true;
        if (address(transferRestrictor) == address(0)) return false;
        return transferRestrictor.isBlacklisted(account);
    }

    /// ------------------ Split ------------------ ///

    /// @notice Deploy and configure a new BridgedERC20 for a split
    /// @param _splitMultiple Ratio of new token to old token
    /// @param _reverseSplit True if this is a reverse split
    /// @param legacyName New name for legacy token
    /// @param legacySymbol New symbol for legacy token
    /// @return newToken Address of new token
    /// @dev After split: no mint, no burn other than by child token
    function split(uint8 _splitMultiple, bool _reverseSplit, string calldata legacyName, string calldata legacySymbol)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (BridgedERC20 newToken)
    {
        if (address(childToken) != address(0)) revert TokenSplit();
        if (_splitMultiple == 0) revert ZeroMultiple();

        // Deploy new token via factory delegatecall
        // This prevents a circular dependency on BridgedERC20 introduced by using "new"
        bytes memory returnData = factory.functionDelegateCall(
            abi.encodeWithSelector(
                IBridgedERC20Factory.createBridgedERC20.selector,
                owner(),
                name(),
                symbol(),
                disclosures,
                transferRestrictor,
                _splitMultiple,
                _reverseSplit,
                factory
            )
        );
        newToken = BridgedERC20(abi.decode(returnData, (address)));

        // Set child token
        childToken = newToken;

        // Update name and symbol
        setName(legacyName);
        setSymbol(legacySymbol);

        // Emit split event
        emit Split(newToken, _splitMultiple, _reverseSplit, legacyName, legacySymbol);
    }

    /// @notice Convert legacy tokens to new tokens at slit ratio
    /// @param amount Amount of legacy tokens to convert
    function convert(uint256 amount) external returns (uint256 newAmount) {
        // Move legacy tokens to this contract
        BridgedERC20(deployer).transferFrom(msg.sender, address(this), amount);

        // Burn legacy tokens
        BridgedERC20(deployer).burn(amount);

        // Split math
        if (reverseSplit) {
            newAmount = amount / splitMultiple;
        } else {
            newAmount = amount * splitMultiple;
        }

        // Mint new tokens
        _mint(msg.sender, newAmount);
    }
}
