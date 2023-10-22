// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {IFeeSchedule} from "./IFeeSchedule.sol";

/**
 * @notice This contract handles the fee schedules for BUY/SELL operations
 */

contract FeeSchedule is IFeeSchedule, Ownable2Step {
    /// ------------------ State Variables ------------------ ///

    /// @notice Mapping from operation type to its corresponding fee.
    mapping(address account => bool isZeroFee) public accountZeroFee;
    mapping(address account => mapping(bool sell => Fee)) public accountFees;

    /// ------------------ Setters ------------------ ///

    /**
     * @notice Sets the fee for a given operation type.
     * @param _sell The type of operation (BUY or SELL).
     * @param newFee The new fee to be set for the operation.
     */
    function setFees(address _account, Fee memory newFee, bool _sell) external onlyOwner {
        accountFees[_account][_sell] = newFee;
        emit FeesSet(_sell, newFee.percentageFeeRate, newFee.perOrderFee);
    }

    /**
     * @notice Sets the zero fee state for the contract.
     * @param _account The address of the account for which the zero fee state is to be set.
     * @param _isZeroFee The new zero fee state.
     */
    function setZeroFeeState(address _account, bool _isZeroFee) external onlyOwner {
        accountZeroFee[_account] = _isZeroFee;
        emit ZeroFeeStateSet(_account, _isZeroFee);
    }

    /// ------------------ Getters ------------------ ///

    /**
     * @notice Retrieves the fee for a given operation type.
     * @param _account The address of the account for which the fee is to be fetched.
     * @param _sell The type of operation (BUY or SELL).
     * @return The percentage fee rate and the per order fee for the operation.
     */
    function getFees(address _account, bool _sell) external view returns (uint24, uint64) {
        Fee memory fee = accountFees[_account][_sell];
        return (fee.percentageFeeRate, fee.perOrderFee);
    }
}
