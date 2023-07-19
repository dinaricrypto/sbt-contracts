// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITransferRestrictor} from "./ITransferRestrictor.sol";
import {BridgedERC20} from "./BridgedERC20.sol";

import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract TokenManager is Ownable2Step {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Strings for uint256;

    /// ------------------ Types ------------------ ///

    struct SplitInfo {
        BridgedERC20 newToken;
        uint8 multiple;
        bool reverseSplit;
    }

    /// @dev Emitted when a split is performed
    event Split(BridgedERC20 indexed legacyToken, BridgedERC20 indexed newToken, uint8 multiple, bool reverseSplit);

    error TokenNotFound();
    error InvalidMultiple();
    error SplitNotFound();

    /// ------------------ State ------------------ ///

    /// @dev Suffix to append to new token names
    string public nameSuffix = " - Dinari";

    /// @dev Suffix to append to new token symbols
    string public symbolSuffix = ".d";

    /// @dev Transfer restrictor contract
    ITransferRestrictor public transferRestrictor;

    /// @dev Link to disclosures
    string public disclosures = "";

    /// @dev List of current tokens
    EnumerableSet.AddressSet private _currentTokens;

    /// @dev Mapping of legacy tokens to split information
    mapping(BridgedERC20 => SplitInfo) public splits;

    /// ------------------ Initialization ------------------ ///

    /// @notice Initialize contract
    /// @param transferRestrictor_ Contract to restrict transfers
    constructor(ITransferRestrictor transferRestrictor_) {
        transferRestrictor = transferRestrictor_;
    }

    /// ------------------ Getters ------------------ ///

    /// @notice Get number of tokens
    function getNumTokens() external view returns (uint256) {
        return _currentTokens.length();
    }

    /// @notice Get token at index
    function getTokenAt(uint256 index) external view returns (address) {
        return _currentTokens.at(index);
    }

    /// @notice Get all tokens
    /// @dev Returns a copy of the internal array
    function getTokens() external view returns (address[] memory) {
        return _currentTokens.values();
    }

    /// ------------------ Setters ------------------ ///

    /// @notice Set suffix to append to new token names
    /// @dev Only callable by owner
    function setNameSuffix(string memory nameSuffix_) external onlyOwner {
        nameSuffix = nameSuffix_;
    }

    /// @notice Set suffix to append to new token symbols
    /// @dev Only callable by owner
    function setSymbolSuffix(string memory symbolSuffix_) external onlyOwner {
        symbolSuffix = symbolSuffix_;
    }

    /// @notice Set transfer restrictor contract
    /// @dev Only callable by owner
    function setTransferRestrictor(ITransferRestrictor transferRestrictor_) external onlyOwner {
        transferRestrictor = transferRestrictor_;
    }

    /// @notice Set link to disclosures
    /// @dev Only callable by owner
    function setDisclosures(string memory disclosures_) external onlyOwner {
        disclosures = disclosures_;
    }

    /// ------------------ Token Deployment ------------------ ///

    /// @notice Deploy a new token
    /// @param owner Owner of new token
    /// @param name Name of new token, without suffix
    /// @param symbol Symbol of new token, without suffix
    function deployNewToken(address owner, string memory name, string memory symbol)
        external
        returns (BridgedERC20 newToken)
    {
        // Deploy new token
        newToken = new BridgedERC20(
            owner,
            string.concat(name, nameSuffix),
            string.concat(symbol, symbolSuffix),
            disclosures,
            transferRestrictor
        );
        // Add to list of tokens
        _currentTokens.add(address(newToken));
    }

    /// ------------------ Split ------------------ ///

    /// @notice Split a token
    /// @param token Token to split
    /// @param multiple Multiple to split by
    /// @param reverseSplit Whether to perform a reverse split
    function split(BridgedERC20 token, uint8 multiple, bool reverseSplit) external returns (BridgedERC20 newToken) {
        // Check if token is in list of tokens
        if (!_currentTokens.contains(address(token))) revert TokenNotFound();
        // Check if split multiple is valid
        if (multiple == 0) revert InvalidMultiple();

        // Remove legacy token from list of tokens
        _currentTokens.remove(address(token));

        // Get current token name
        string memory name = token.name();
        string memory symbol = token.symbol();

        // Deploy new token
        newToken = new BridgedERC20(
            token.owner(),
            name,
            symbol,
            disclosures,
            transferRestrictor
        );
        // Add to list of tokens
        _currentTokens.add(address(newToken));
        // Map legacy token to split information
        splits[token] = SplitInfo({newToken: newToken, multiple: multiple, reverseSplit: reverseSplit});

        // Emit event
        emit Split(token, newToken, multiple, reverseSplit);

        // Set split on legacy token
        token.setSplit();

        // Rename legacy token
        string memory timestamp = block.timestamp.toString();
        token.setName(string.concat(name, " - pre", timestamp));
        token.setSymbol(string.concat(symbol, ".p", timestamp));
    }

    /// @notice Convert a token amount to current token after split
    /// @param token Token to convert
    /// @param amount Amount to convert
    /// @return currentToken Current token minted to user
    /// @return resultAmount Amount of current token minted to user
    /// @dev Accounts for multiple splits and returns the current token
    function convert(BridgedERC20 token, uint256 amount)
        external
        returns (BridgedERC20 currentToken, uint256 resultAmount)
    {
        // Check if token has been split
        SplitInfo memory _split = splits[token];
        if (address(_split.newToken) == address(0)) revert SplitNotFound();

        // Apply splits
        currentToken = _split.newToken;
        resultAmount = splitAmount(_split.multiple, _split.reverseSplit, amount);
        while (address(splits[currentToken].newToken) != address(0)) {
            _split = splits[currentToken];
            currentToken = _split.newToken;
            resultAmount = splitAmount(_split.multiple, _split.reverseSplit, resultAmount);
        }

        // Transfer tokens
        token.transferFrom(msg.sender, address(this), amount);
        token.burn(amount);
        currentToken.mint(msg.sender, resultAmount);
    }

    /// @notice Amount of token produced by a split
    /// @param multiple Multiple to split by
    /// @param reverseSplit Whether to perform a reverse split
    /// @param amount Amount to split
    function splitAmount(uint8 multiple, bool reverseSplit, uint256 amount) public pure returns (uint256) {
        // Apply split
        if (reverseSplit) {
            return amount / multiple;
        } else {
            return amount * multiple;
        }
    }
}
