// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {OFTCoreUpgradeable} from "oft-upgradeable/src/oft/OFTCoreUpgradeable.sol";
import {IDShare, ITransferRestrictor} from "./IDShare.sol";
import {ERC20Rebasing} from "./ERC20Rebasing.sol";

/// @notice Core token contract for bridged assets. Rebases on stock splits.
/// ERC20 with minter, burner, and blacklist
/// Uses solady ERC20 which allows EIP-2612 domain separator with `name` changes
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/dShare.sol)
contract DShare is
    IDShare,
    Initializable,
    ERC20Rebasing,
    AccessControlDefaultAdminRulesUpgradeable,
    OFTCoreUpgradeable
{
    // TODO: create multichain rebasing process. rebasing while maintaining in-flight crosschain orders sounds problematic.
    // TODO: test crosschain transfers
    // TODO: should we rate limit oft mint/burn?
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

    // keccak256(abi.encode(uint256(keccak256("dinaricrypto.storage.DShare")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant dShareStorageLocation = 0x7315beb2381679795e06870021c0fca5deb85616e29e098c2e7b7e488f185800;

    function _getdShareStorage() private pure returns (dShareStorage storage $) {
        assembly {
            $.slot := dShareStorageLocation
        }
    }

    /// ------------------ Initialization ------------------ ///

    function initialize(
        address _owner,
        string memory _name,
        string memory _symbol,
        ITransferRestrictor _transferRestrictor,
        address _lzEndpoint
    ) public initializer {
        __AccessControlDefaultAdminRules_init_unchained(0, _owner);
        __OFTCore_init(decimals(), _lzEndpoint, _owner);

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

    // ------------------ OFT ------------------ //

    /**
     * @dev Retrieves the OFT contract version.
     * @return major The major version.
     * @return minor The minor version.
     *
     * @dev major version: Indicates a cross-chain compatible msg encoding with other OFTs.
     * @dev minor version: Indicates a version within the local chains context. eg. OFTAdapter vs. OFT
     * @dev For example, if a new feature is added to the OFT contract, the minor version will be incremented.
     * @dev If a new feature is added to the OFT cross-chain msg encoding, the major version will be incremented.
     * ie. localOFT version(1,1) CAN send messages to remoteOFT version(1,2)
     */
    function oftVersion() external pure returns (uint64 major, uint64 minor) {
        return (1, 1);
    }

    /**
     * @dev Retrieves the address of the underlying ERC20 implementation.
     * @return The address of the OFT token.
     *
     * @dev In the case of OFT, address(this) and erc20 are the same contract.
     */
    function token() external view returns (address) {
        return address(this);
    }

    function owner()
        public
        view
        override(AccessControlDefaultAdminRulesUpgradeable, OwnableUpgradeable)
        returns (address)
    {
        return AccessControlDefaultAdminRulesUpgradeable.owner();
    }

    /**
     * @dev Burns tokens from the sender's specified balance.
     * @param _amountToSendLD The amount of tokens to send in local decimals.
     * @param _minAmountToCreditLD The minimum amount to credit in local decimals.
     * @param _dstEid The destination chain ID.
     * @return amountDebitedLD The amount of tokens ACTUALLY debited in local decimals.
     * @return amountToCreditLD The amount of tokens to credit in local decimals.
     */
    function _debitSender(uint256 _amountToSendLD, uint256 _minAmountToCreditLD, uint32 _dstEid)
        internal
        virtual
        override
        returns (uint256 amountDebitedLD, uint256 amountToCreditLD)
    {
        (amountDebitedLD, amountToCreditLD) = _debitView(_amountToSendLD, _minAmountToCreditLD, _dstEid);

        // @dev In NON-default OFT, amountDebited could be 100, with a 10% fee, the credited amount is 90,
        // therefore amountDebited CAN differ from amountToCredit.

        // @dev Default OFT burns on src.
        _burn(msg.sender, amountDebitedLD);
    }

    /**
     * @dev Burns tokens that have been sent into this contract.
     * @param _minAmountToReceiveLD The minimum amount to receive in local decimals.
     * @param _dstEid The destination chain ID.
     * @return amountDebitedLD The amount of tokens ACTUALLY debited in local decimals.
     * @return amountToCreditLD The amount of tokens to credit in local decimals.
     */
    function _debitThis(uint256 _minAmountToReceiveLD, uint32 _dstEid)
        internal
        virtual
        override
        returns (uint256 amountDebitedLD, uint256 amountToCreditLD)
    {
        // @dev This is the push method, where at any point in the transaction, the OFT receives tokens and they can be sent by the caller.
        // @dev This SHOULD be done atomically, otherwise any caller can spend tokens that are owned by the contract.
        // @dev In the NON-default case where fees are stored in the contract, there should be a value reserved via a global state.
        // eg. balanceOf(address(this)) - accruedFees;
        (amountDebitedLD, amountToCreditLD) = _debitView(balanceOf(address(this)), _minAmountToReceiveLD, _dstEid);

        // @dev Default OFT burns on src.
        _burn(address(this), amountDebitedLD);

        // @dev When sending tokens direct to the OFT contract,
        // there is NOT a default mechanism to capture the dust that MIGHT get left in the contract.
        // If you want to refund this dust, will need to add another function to return it.
    }

    /**
     * @dev Credits tokens to the specified address.
     * @param _to The address to credit the tokens to.
     * @param _amountToCreditLD The amount of tokens to credit in local decimals.
     * @dev _srcEid The source chain ID.
     * @return amountReceivedLD The amount of tokens ACTUALLY received in local decimals.
     */
    function _credit(address _to, uint256 _amountToCreditLD, uint32 /*_srcEid*/ )
        internal
        virtual
        override
        returns (uint256 amountReceivedLD)
    {
        // @dev Default OFT mints on dst.
        _mint(_to, _amountToCreditLD);
        // @dev In the case of NON-default OFT, the amountToCreditLD MIGHT not == amountReceivedLD.
        return _amountToCreditLD;
    }
}
