// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

contract FeeSchedule is Ownable2Step {
    /// ------------------ Types ------------------ ///
    event FeeScheduleUpdated(uint256 perOrderFee, uint256 percentageFee);

    /// ------------------ State ------------------ ///
    uint64 public perOrderFee;
    uint24 public percentageFeeRate;

    /// ------------------ Constructor ------------------ ///

    constructor(uint64 _perOrderFee, uint24 _percentageFeeRate) {
        perOrderFee = _perOrderFee;
        percentageFeeRate = _percentageFeeRate;
    }

    /// ------------------ Setters ------------------ ///
    /**
     * @notice Set the fees for the account.
     * @dev Only the contract owner or authorized entities should be allowed to call this.
     * @param _perOrderFee The flat fee per order.
     * @param _percentageFeeRate The percentage fee rate.
     */
    function setFees(uint64 _perOrderFee, uint24 _percentageFeeRate) external onlyOwner {
        perOrderFee = _perOrderFee;
        percentageFeeRate = _percentageFeeRate;
        emit FeeScheduleUpdated(_perOrderFee, _percentageFeeRate);
    }

    /// ------------------ Getters ------------------ ///

    /**
     * @notice Fetch the fee rates based on the given criteria.
     * @param requester The address making the request (could be used for advanced fee logic).
     * @param isBuy True if it's a buy order, false if it's a sell order.
     * @return perOrder The flat fee for the order.
     * @return percentage The percentage fee rate for the order.
     */
    function getFees(address requester, bool isBuy) external view returns (uint64 perOrder, uint24 percentage) {
        // TODO: Implement any advanced fee logic based on the requester or buy/sell type
        return (perOrderFee, percentageFeeRate);
    }
}
