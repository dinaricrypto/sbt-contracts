// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {
    UUPSUpgradeable,
    Initializable
} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {TransferRestrictor} from "./TransferRestrictor.sol";
import {DShare} from "./DShare.sol";
import {WrappedDShare} from "./WrappedDShare.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";

///@notice Factory to create new dShares
///@author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/DShareFactory.sol)
contract DShareFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    error ZeroAddress();

    /// @notice Emitted when a new dShare is created
    event DShareCreated(address indexed dShare, address indexed wrappedDShare, string indexed symbol, string name);
    event NewTransferRestrictorSet(address indexed transferRestrictor);

    struct DShareFactoryStorage {
        UpgradeableBeacon _dShareBeacon;
        UpgradeableBeacon _wrappedDShareBeacon;
        TransferRestrictor _transferRestrictor;
    }

    // keccak256(abi.encode(uint256(keccak256("dinaricrypto.storage.DShareFactory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DShareFactoryStorageLocation =
        0x624c7938caaf85453d1e344eb5510e0efc5d0cf6f1e8d4a400187ed89d63af00;

    function _getDShareFactoryStorage() internal pure returns (DShareFactoryStorage storage $) {
        assembly {
            $.slot := DShareFactoryStorageLocation
        }
    }

    function initialize(
        address _owner,
        UpgradeableBeacon _dShareBeacon,
        UpgradeableBeacon _wrappedDShareBeacon,
        TransferRestrictor _transferRestrictor
    ) external initializer {
        if (
            address(_dShareBeacon) == address(0) || address(_wrappedDShareBeacon) == address(0)
                || address(_transferRestrictor) == address(0)
        ) revert ZeroAddress();
        __Ownable_init(_owner);

        DShareFactoryStorage storage $ = _getDShareFactoryStorage();
        $._dShareBeacon = _dShareBeacon;
        $._wrappedDShareBeacon = _wrappedDShareBeacon;
        $._transferRestrictor = _transferRestrictor;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @notice Sets a new transfer restrictor for the dShare
    /// @param _transferRestrictor New transfer restrictor
    function setNewTransferRestrictor(TransferRestrictor _transferRestrictor) external {
        if (address(_transferRestrictor) == address(0)) revert ZeroAddress();
        DShareFactoryStorage storage $ = _getDShareFactoryStorage();
        $._transferRestrictor = _transferRestrictor;
        emit NewTransferRestrictorSet(address(_transferRestrictor));
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
    ) external returns (address dShare, address wrappedDShare) {
        DShareFactoryStorage storage $ = _getDShareFactoryStorage();
        dShare = address(
            new BeaconProxy(
                address($._dShareBeacon),
                abi.encodeCall(DShare.initialize, (owner, name, symbol, $._transferRestrictor))
            )
        );
        wrappedDShare = address(
            new BeaconProxy(
                address($._wrappedDShareBeacon),
                abi.encodeCall(WrappedDShare.initialize, (owner, DShare(dShare), wrappedName, wrappedSymbol))
            )
        );

        emit DShareCreated(dShare, wrappedDShare, symbol, name);
    }
}
