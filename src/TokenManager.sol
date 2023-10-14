// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITokenManager} from "./ITokenManager.sol";
import {ITransferRestrictor} from "./ITransferRestrictor.sol";
import {dShare} from "./dShare.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

// TODO: migrate existing tokens
contract TokenManager is ITokenManager, Ownable2Step {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Strings for uint256;

    /// ------------------ Types ------------------ ///

    struct SplitInfo {
        dShare newToken;
        uint8 multiple;
        bool reverseSplit;
    }

    event NameSuffixSet(string nameSuffix);
    event SymbolSuffixSet(string symbolSuffix);
    event TransferRestrictorSet(ITransferRestrictor transferRestrictor);
    event DisclosuresSet(string disclosures);
    /// @dev Emitted when a new token is deployed
    event NewToken(dShare indexed token);
    /// @dev Emitted when a split is performed
    event Split(
        dShare indexed legacyToken, dShare indexed newToken, uint8 multiple, bool reverseSplit, uint256 aggregateSupply
    );

    error TokenNotFound();
    error InvalidMultiple();
    error SplitNotFound();
    error AlreadySplit();

    /// ------------------ State ------------------ ///

    /// @notice Suffix to append to new token names
    string public nameSuffix = " - Dinari";

    /// @notice Suffix to append to new token symbols
    string public symbolSuffix = ".d";

    /// @notice Transfer restrictor contract
    ITransferRestrictor public transferRestrictor;

    /// @notice Link to disclosures
    string public disclosures = "";

    /// @dev List of current tokens
    EnumerableSet.AddressSet private _currentTokens;

    /// @notice Mapping of legacy tokens to split information
    mapping(dShare => SplitInfo) public splits;

    /// @notice Mapping of new tokens to legacy tokens
    /// @dev Allows traversal up and down the split chain
    mapping(dShare => dShare) public parentToken;

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

    /// @inheritdoc ITokenManager
    function isCurrentToken(address token) public view returns (bool) {
        return _currentTokens.contains(token);
    }

    /// ------------------ Setters ------------------ ///

    /// @notice Set suffix to append to new token names
    /// @dev Only callable by owner
    function setNameSuffix(string memory nameSuffix_) external onlyOwner {
        nameSuffix = nameSuffix_;
        emit NameSuffixSet(nameSuffix_);
    }

    /// @notice Set suffix to append to new token symbols
    /// @dev Only callable by owner
    function setSymbolSuffix(string memory symbolSuffix_) external onlyOwner {
        symbolSuffix = symbolSuffix_;
        emit SymbolSuffixSet(symbolSuffix_);
    }

    /// @notice Set transfer restrictor contract
    /// @dev Only callable by owner
    function setTransferRestrictor(ITransferRestrictor transferRestrictor_) external onlyOwner {
        transferRestrictor = transferRestrictor_;
        emit TransferRestrictorSet(transferRestrictor_);
    }

    /// @notice Set link to disclosures
    /// @dev Only callable by owner
    function setDisclosures(string memory disclosures_) external onlyOwner {
        disclosures = disclosures_;
        emit DisclosuresSet(disclosures_);
    }

    /// ------------------ Token Deployment ------------------ ///

    /// @notice Deploy a new token
    /// @param owner Owner of new token
    /// @param name Name of new token, without suffix
    /// @param symbol Symbol of new token, without suffix
    /// @dev Only callable by owner
    function deployNewToken(address owner, string memory name, string memory symbol)
        external
        onlyOwner
        returns (dShare newToken)
    {
        // Deploy new token
        newToken = new dShare(
            owner,
            string.concat(name, nameSuffix),
            string.concat(symbol, symbolSuffix),
            disclosures,
            transferRestrictor
        );
        // Add to list of tokens
        assert(_currentTokens.add(address(newToken)));
        emit NewToken(newToken);
    }

    /// ------------------ Split Views ------------------ ///

    /// @notice Get active token for any parent token
    /// @param token Token to get active token for
    function getCurrentToken(dShare token) public view returns (dShare) {
        dShare _token = token;
        dShare _nextToken;
        while (address(_nextToken = splits[_token].newToken) != address(0)) {
            _token = _nextToken;
        }
        return _token;
    }

    /// @notice Calculate total aggregate supply after split
    /// @param token Token to calculate supply expansion for
    /// @param multiple Multiple to split by
    /// @param reverseSplit Whether to perform a reverse split
    /// @dev Accounts for all splits and supply volume conversions
    function getSupplyExpansion(dShare token, uint8 multiple, bool reverseSplit) public view returns (uint256) {
        uint256 aggregateSupply = getAggregateSupply(token);

        // Apply current split
        return splitAmount(multiple, reverseSplit, aggregateSupply);
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

    /// @notice Get root parent token
    /// @param token Token to get root parent for
    function getRootParent(dShare token) public view returns (dShare) {
        dShare _parentToken = token;
        while (address(parentToken[_parentToken]) != address(0)) {
            _parentToken = parentToken[_parentToken];
        }
        return _parentToken;
    }

    /// @notice Calculate total aggregate supply
    /// @param token Token to calculate supply for
    /// @dev Accounts for all splits and supply volume conversions
    function getAggregateSupply(dShare token) public view returns (uint256 aggregateSupply) {
        // Get root parent
        dShare _parentToken = getRootParent(token);
        // Accumulate supply expansion from parents
        aggregateSupply = 0;
        if (address(_parentToken) != address(token)) {
            SplitInfo memory _split = splits[_parentToken];
            aggregateSupply = splitAmount(_split.multiple, _split.reverseSplit, _parentToken.totalSupply());
            while (address(_split.newToken) != address(token)) {
                // slither-disable-next-line calls-loop
                aggregateSupply += _split.newToken.totalSupply();
                _split = splits[_split.newToken];
                aggregateSupply = splitAmount(_split.multiple, _split.reverseSplit, aggregateSupply);
            }
        }
        // Include current token supply
        aggregateSupply += token.totalSupply();
    }

    /// @notice Calculate total aggregate balance of account after split
    /// @param token Token to calculate balance expansion for
    /// @param account Account to calculate balance for
    function getAggregateBalanceOf(dShare token, address account) public view returns (uint256 aggregateBalance) {
        // Get root parent
        dShare _parentToken = getRootParent(token);
        // Accumulate supply expansion from parents
        aggregateBalance = 0;
        if (address(_parentToken) != address(token)) {
            SplitInfo memory _split = splits[_parentToken];
            aggregateBalance = splitAmount(_split.multiple, _split.reverseSplit, _parentToken.balanceOf(account));
            while (address(_split.newToken) != address(token)) {
                // slither-disable-next-line calls-loop
                aggregateBalance += _split.newToken.balanceOf(account);
                _split = splits[_split.newToken];
                aggregateBalance = splitAmount(_split.multiple, _split.reverseSplit, aggregateBalance);
            }
        }
        // Include current token balance
        aggregateBalance += token.balanceOf(account);
    }

    /// ------------------ Split ------------------ ///

    /// @notice Split a token
    /// @param token Token to split
    /// @param multiple Multiple to split by
    /// @param reverseSplit Whether to perform a reverse split
    /// @dev Only callable by owner
    function split(dShare token, uint8 multiple, bool reverseSplit)
        external
        onlyOwner
        returns (dShare newToken, uint256 aggregateSupply)
    {
        // Check if split multiple is valid
        if (multiple < 2) revert InvalidMultiple();
        // Remove legacy token from list of tokens
        if (!_currentTokens.remove(address(token))) revert TokenNotFound();
        // Check if split exceeds max supply of type(uint256).max
        aggregateSupply = getSupplyExpansion(token, multiple, reverseSplit);

        // Get current token name
        string memory name = token.name();
        string memory symbol = token.symbol();

        // Deploy new token
        newToken = new dShare(
            token.owner(),
            name,
            symbol,
            disclosures,
            transferRestrictor
        );
        // Add to list of tokens
        assert(_currentTokens.add(address(newToken)));
        // Map legacy token to split information
        splits[token] = SplitInfo({newToken: newToken, multiple: multiple, reverseSplit: reverseSplit});
        // Map new token to legacy token
        parentToken[newToken] = token;

        // Emit event
        emit Split(token, newToken, multiple, reverseSplit, aggregateSupply);

        // Set split on legacy token
        token.setSplit();

        // Rename legacy token
        string memory timestamp = block.timestamp.toString();
        token.setName(string.concat(name, " - pre", timestamp));
        token.setSymbol(string.concat(symbol, ".p", timestamp));
    }

    /// @inheritdoc ITokenManager
    function convert(dShare token, uint256 amount) public returns (dShare currentToken, uint256 resultAmount) {
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
        // slither-disable-next-line unchecked-transfer
        token.transferFrom(msg.sender, address(this), amount);
        token.burn(amount);
        currentToken.mint(msg.sender, resultAmount);
    }

    // @inheritdoc ITokenManager
    function sweepConvert(dShare currentToken) external {
        dShare _parentToken = parentToken[currentToken];
        while (address(_parentToken) != address(0)) {
            uint256 parentBalance = _parentToken.balanceOf(msg.sender);
            convert(_parentToken, parentBalance);
            _parentToken = parentToken[_parentToken];
        }
    }
}
