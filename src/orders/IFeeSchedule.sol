// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

interface IFeeSchedule {
    struct Fee {
        uint64 perOrderFee;
        uint24 percentageFeeRate;
    }

    // Events
    event FeesSet(bool sell, uint24 percentageFeeRate, uint64 perOrderFee);
    event ZeroFeeStateSet(address account, bool isZeroFee);

    function accountFees(address, bool) external view returns (uint64 perOrderFee, uint24 percentageFeeRate);
    function accountZeroFee(address account) external view returns (bool);

    // Setters
    function setFees(address _account, Fee memory newFee, bool _sell) external;
    function setZeroFeeState(address _account, bool _isZeroFee) external;

    // Getters
    function getFees(address _account, bool _sell) external view returns (uint24, uint64);
}
