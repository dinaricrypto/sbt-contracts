// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {xERC4626} from "./xERC4626.sol";
import {dShare} from "./dShare.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ITransferRestrictor} from "./ITransferRestrictor.sol";

/**
 * @title xdShare Contract
 * @dev This contract acts as a wrapper over the dShare token, providing additional functionalities.
 *         It serves as a reinvestment token that uses dShare as the underlying token.
 *         Additionally, it employs the ERC4626 standard for its operations.
 * @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/xdShare.sol)
 */

// slither-disable-next-line missing-inheritance
contract xdShare is Ownable, xERC4626 {
    /// @notice Reference to the underlying dShare contract.
    dShare public immutable underlyingDShare;

    /**
     * @dev Initializes a new instance of the xdShare contract.
     * @param _dShare The address of the underlying dShare token.
     * @param _rewardsCycleLength Length of the rewards cycle.
     */
    constructor(dShare _dShare, uint32 _rewardsCycleLength) xERC4626(_rewardsCycleLength) {
        underlyingDShare = _dShare;
    }

    /**
     * @dev Returns the name of the xdShare token.
     * @return A string representing the name.
     */
    function name() public view virtual override returns (string memory) {
        return string(abi.encodePacked("Reinvesting ", underlyingDShare.symbol()));
    }

    /**
     * @dev Returns the symbol of the xdShare token.
     * @return A string representing the symbol.
     */
    function symbol() public view virtual override returns (string memory) {
        return string(abi.encodePacked(underlyingDShare.symbol(), ".x"));
    }

    /**
     * @dev Returns the address of the underlying asset.
     * @return The address of the underlying dShare token.
     */
    function asset() public view virtual override returns (address) {
        return address(underlyingDShare);
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting and burning.
     * @param from Address of the sender.
     * @param to Address of the receiver.
     */
    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        if (to == address(0)) revert dShare.Unauthorized();

        ITransferRestrictor restrictor = underlyingDShare.transferRestrictor();

        if (address(restrictor) != address(0)) {
            restrictor.requireNotRestricted(from, to);
        }
    }

    /**
     * @dev Checks if an account is blacklisted in the underlying dShare contract.
     * @param account Address of the account to check.
     * @return True if the account is blacklisted, false otherwise.
     */
    function isBlacklisted(address account) external view returns (bool) {
        ITransferRestrictor restrictor = underlyingDShare.transferRestrictor();
        if (address(restrictor) == address(0)) return false;
        return restrictor.isBlacklisted(account);
    }
}
