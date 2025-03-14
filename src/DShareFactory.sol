// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {IDShareFactory} from "./IDShareFactory.sol";
import {TransferRestrictor} from "./TransferRestrictor.sol";
import {DShare} from "./DShare.sol";
import {WrappedDShare} from "./WrappedDShare.sol";
import {ControlledUpgradeable} from "./deployment/ControlledUpgradeable.sol";

///@notice Factory to create new dShares
///@author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/DShareFactory.sol)
contract DShareFactory is IDShareFactory, ControlledUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// ------------------------------- Types -----------------------------------

    error ZeroAddress();
    error Mismatch();
    error PreviouslyAnnounced();

    event NewTransferRestrictorSet(address indexed transferRestrictor);

    /// ------------------------------- Storage -----------------------------------
    struct DShareFactoryStorage {
        address _dShareBeacon;
        address _wrappedDShareBeacon;
        address _transferRestrictor;
        EnumerableSet.AddressSet _wrappedDShares;
        EnumerableSet.AddressSet _dShares;
    }

    // keccak256(abi.encode(uint256(keccak256("dinaricrypto.storage.DShareFactory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DShareFactoryStorageLocation =
        0x624c7938caaf85453d1e344eb5510e0efc5d0cf6f1e8d4a400187ed89d63af00;

    function _getDShareFactoryStorage() internal pure returns (DShareFactoryStorage storage $) {
        assembly {
            $.slot := DShareFactoryStorageLocation
        }
    }

    /// ------------------------------- Version -----------------------------------------

    /// @notice Version of the contract
    function version() public view override returns (uint8) {
        return 1;
    }

    /// @notice Public version of the contract
    function publicVersion() public view override returns (string memory) {
        return "1.0.0";
    }
    /// ------------------------------- Initialization -----------------------------------

    function initialize(
        address _owner,
        address _upgrader,
        address _dShareBeacon,
        address _wrappedDShareBeacon,
        address _transferRestrictor
    ) external reinitializer(version()) {
        if (_dShareBeacon == address(0) || _wrappedDShareBeacon == address(0) || _transferRestrictor == address(0)) {
            revert ZeroAddress();
        }
        __ControlledUpgradeable_init(_owner, _upgrader);

        DShareFactoryStorage storage $ = _getDShareFactoryStorage();
        $._dShareBeacon = _dShareBeacon;
        $._wrappedDShareBeacon = _wrappedDShareBeacon;
        $._transferRestrictor = _transferRestrictor;
    }

    function reinitialize(address owner, address upgrader) external reinitializer(version()) {
        __ControlledUpgradeable_init(owner, upgrader);
    }

    /// @dev In-place initialization of dShares storage for existing factory
    function initializeV2() external onlyRole(DEFAULT_ADMIN_ROLE) reinitializer(2) {
        DShareFactoryStorage storage $ = _getDShareFactoryStorage();
        for (uint256 i = 0; i < $._wrappedDShares.length(); i++) {
            // slither-disable-next-line unused-return,calls-loop
            $._dShares.add(WrappedDShare($._wrappedDShares.at(i)).asset());
        }
        assert($._dShares.length() == $._wrappedDShares.length());
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// ------------------------------- Getters -----------------------------------

    /// @notice Gets the dShare beacon
    function getDShareBeacon() external view returns (address) {
        DShareFactoryStorage storage $ = _getDShareFactoryStorage();
        return $._dShareBeacon;
    }

    /// @notice Gets the wrapped dShare beacon
    function getWrappedDShareBeacon() external view returns (address) {
        DShareFactoryStorage storage $ = _getDShareFactoryStorage();
        return $._wrappedDShareBeacon;
    }

    /// @notice Gets the transfer restrictor for the dShare
    function getTransferRestrictor() external view returns (address) {
        DShareFactoryStorage storage $ = _getDShareFactoryStorage();
        return $._transferRestrictor;
    }

    /// ------------------------------- Admin -----------------------------------

    /// @notice Sets a new transfer restrictor for the dShare
    /// @param _transferRestrictor New transfer restrictor
    function setNewTransferRestrictor(address _transferRestrictor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_transferRestrictor == address(0)) revert ZeroAddress();
        DShareFactoryStorage storage $ = _getDShareFactoryStorage();
        $._transferRestrictor = _transferRestrictor;
        emit NewTransferRestrictorSet(_transferRestrictor);
    }

    /// ------------------------------- Factory -----------------------------------

    function isTokenDShare(address token) external view returns (bool) {
        DShareFactoryStorage storage $ = _getDShareFactoryStorage();
        return $._dShares.contains(token);
    }

    function isTokenWrappedDShare(address token) external view returns (bool) {
        DShareFactoryStorage storage $ = _getDShareFactoryStorage();
        return $._wrappedDShares.contains(token);
    }

    /// @notice Gets list of all dShares and wrapped dShares
    /// @return dShares List of all dShares
    /// @return wrappedDShares List of all wrapped dShares
    /// @dev This function can be expensive
    function getDShares() external view returns (address[] memory, address[] memory) {
        DShareFactoryStorage storage $ = _getDShareFactoryStorage();
        address[] memory wrappedDShares = $._wrappedDShares.values();
        address[] memory dShares = new address[](wrappedDShares.length);
        for (uint256 i = 0; i < wrappedDShares.length; i++) {
            // slither-disable-next-line calls-loop
            dShares[i] = WrappedDShare(wrappedDShares[i]).asset();
        }
        return (dShares, wrappedDShares);
    }

    /// @notice Creates a new dShare
    /// @param owner of the proxy
    /// @param name Name of the dShare
    /// @param symbol Symbol of the dShare
    /// @param wrappedName Name of the wrapped dShare
    /// @param wrappedSymbol Symbol of the wrapped dShare
    /// @return dShare Address of the new dShare
    function createDShare(
        address owner,
        string memory name,
        string memory symbol,
        string memory wrappedName,
        string memory wrappedSymbol
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address dShare, address wrappedDShare) {
        DShareFactoryStorage storage $ = _getDShareFactoryStorage();
        dShare = address(
            new BeaconProxy(
                address($._dShareBeacon),
                abi.encodeCall(DShare.initialize, (owner, name, symbol, TransferRestrictor($._transferRestrictor)))
            )
        );
        wrappedDShare = address(
            new BeaconProxy(
                address($._wrappedDShareBeacon),
                abi.encodeCall(WrappedDShare.initialize, (owner, DShare(dShare), wrappedName, wrappedSymbol))
            )
        );

        // slither-disable-next-line unused-return
        $._dShares.add(dShare);
        // slither-disable-next-line unused-return
        $._wrappedDShares.add(wrappedDShare);
        assert($._dShares.length() == $._wrappedDShares.length());

        // slither-disable-next-line reentrancy-events
        emit DShareAdded(dShare, wrappedDShare, symbol, name);
    }

    /// @notice Announces an existing dShare
    /// @param dShare Address of the dShare
    /// @param wrappedDShare Address of the wrapped dShare
    function announceExistingDShare(address dShare, address wrappedDShare) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (WrappedDShare(wrappedDShare).asset() != dShare) revert Mismatch();

        DShareFactoryStorage storage $ = _getDShareFactoryStorage();
        if (!$._dShares.add(dShare)) revert PreviouslyAnnounced();
        if (!$._wrappedDShares.add(wrappedDShare)) revert PreviouslyAnnounced();
        assert($._dShares.length() == $._wrappedDShares.length());

        emit DShareAdded(dShare, wrappedDShare, DShare(dShare).symbol(), DShare(dShare).name());
    }
}
