// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "prb-math/Common.sol" as PrbMath;
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IOrderFees} from "./IOrderFees.sol";
import {FeeLib} from "../FeeLib.sol";

/// @notice Manages fee calculations for orders.
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/orders/OrderFees.sol)
contract OrderFees is Ownable2Step, IOrderFees {
    /// @dev Emitted when `perOrderFee` and `percentageFeeRate` are set
    event FeeSet(uint64 perOrderFee, uint24 percentageFeeRate);

    /// ------------------ State ------------------ ///

    /// @notice Flat fee per order in ethers decimals
    uint64 public perOrderFee;

    /// @notice Percentage fee take per order in bps
    uint24 public percentageFeeRate;

    /// ------------------ Initialization ------------------ ///

    /// @notice Initialize fees
    /// @param owner Owner of contract
    /// @param _perOrderFee Base flat fee per order in ethers decimals
    /// @param _percentageFeeRate Percentage fee take per order in bps
    /// @dev Percentage fee cannot be 100% or more
    constructor(address owner, uint64 _perOrderFee, uint24 _percentageFeeRate) {
        // Check percentage fee is less than 100%
        FeeLib.checkPercentageFeeRate(_percentageFeeRate);

        // Set owner
        _transferOwnership(owner);

        // Initialize fees
        perOrderFee = _perOrderFee;
        percentageFeeRate = _percentageFeeRate;
    }

    /// ------------------ Update ------------------ ///

    /// @notice Set the base and percentage fees
    /// @param _perOrderFee Base flat fee per order in ethers decimals
    /// @param _percentageFeeRate Percentage fee per order in bps
    /// @dev Only callable by owner
    function setFees(uint64 _perOrderFee, uint24 _percentageFeeRate) external onlyOwner {
        // Check percentage fee is less than 100%
        FeeLib.checkPercentageFeeRate(_percentageFeeRate);

        // Update fees
        perOrderFee = _perOrderFee;
        percentageFeeRate = _percentageFeeRate;
        // Emit new fees
        emit FeeSet(_perOrderFee, _percentageFeeRate);
    }
}
