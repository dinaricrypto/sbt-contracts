// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

/**
 * @notice This contract handles the fee schedules for different types of operations.
 */

contract FeeSchedule is Ownable2Step {
    /// ------------------ Types ------------------ ///

    /**
     * @notice Struct to represent a fee schedule.
     * @param percentageFeeRate The fee rate as a percentage.
     * @param perOrderFee The flat fee per order.
     */
    struct Fee {
        uint64 perOrderFee;
        uint24 percentageFeeRate;
    }

    /**
     * @notice Enum to represent the type of operation.
     */
    enum OperationType {
        BUY,
        SELL
    }

    /// ------------------ Events ------------------ ///

    event FeesSet(OperationType operation, uint24 percentageFeeRate, uint64 perOrderFee);
    event ZeroFeeStateSet(bool isZeroFee);

    /// ------------------ State Variables ------------------ ///

    /// @notice Flag to determine if the operation should have zero fees.
    bool public isZeroFee;

    /// @notice Mapping from operation type to its corresponding fee.
    mapping(OperationType => Fee) public fees;

    /// ------------------ Initialization ------------------ ///

    /**
     * @notice Constructor to set initial buy and sell fees.
     * @param _buyFee Initial fee for buying operations.
     * @param _sellFee Initial fee for selling operations.
     */
    constructor(Fee memory _buyFee, Fee memory _sellFee) {
        fees[OperationType.BUY] = _buyFee;
        fees[OperationType.SELL] = _sellFee;
    }

    /// ------------------ Setters ------------------ ///

    /**
     * @notice Sets the fee for a given operation type.
     * @param operation The type of operation (BUY or SELL).
     * @param newFee The new fee to be set for the operation.
     */
    function setFees(OperationType operation, Fee memory newFee) external onlyOwner {
        fees[operation] = newFee;
        emit FeesSet(operation, newFee.percentageFeeRate, newFee.perOrderFee);
    }

    /**
     * @notice Sets the zero fee state for the contract.
     * @param _isZeroFee The new zero fee state.
     */
    function setZeroFeeState(bool _isZeroFee) external onlyOwner {
        isZeroFee = _isZeroFee;
        emit ZeroFeeStateSet(_isZeroFee);
    }

    /// ------------------ Getters ------------------ ///

    /**
     * @notice Retrieves the fee for a given operation type.
     * @param operation The type of operation (BUY or SELL).
     * @return The percentage fee rate and the per order fee for the operation.
     */
    function getFee(OperationType operation) external view returns (uint24, uint64) {
        Fee memory fee = fees[operation];
        return (fee.percentageFeeRate, fee.perOrderFee);
    }
}
