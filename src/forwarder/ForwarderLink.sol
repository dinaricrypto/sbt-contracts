// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {Forwarder} from "./Forwarder.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "prb-math/Common.sol" as PrbMath;

/// @notice Forwarder using chainlink oracles
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/forwarder/ForwarderLink.sol)
contract ForwarderLink is Forwarder {
    /// ------------------------------- Storage -------------------------------

    address public ethUsdOracle;

    mapping(address => address) public paymentOracle;

    /// ------------------------------- Initialization -------------------------------

    /// @notice Constructs the Forwarder contract.
    /// @dev Initializes the domain separator used for EIP-712 compliant signature verification.
    constructor(address _ethUsdOracle, uint256 initialSellOrderGasCost) Forwarder(initialSellOrderGasCost) {
        ethUsdOracle = _ethUsdOracle;
    }

    /// ------------------------------- Administration -------------------------------

    /**
     * @dev add oracle for eth in usd
     * @param _ethUsdOracle chainlink oracle address
     */
    function setEthUsdOracle(address _ethUsdOracle) external onlyOwner {
        ethUsdOracle = _ethUsdOracle;
        emit EthUsdOracleSet(_ethUsdOracle);
    }

    /**
     * @dev add oracle for a payment token
     * @param paymentToken asset to add oracle
     * @param oracle chainlink oracle address
     */
    function setPaymentOracle(address paymentToken, address oracle) external onlyOwner {
        paymentOracle[paymentToken] = oracle;
        emit PaymentOracleSet(paymentToken, oracle);
    }

    /// ------------------------------- Oracle Usage -------------------------------

    function isSupportedToken(address token) public view override returns (bool) {
        return paymentOracle[token] != address(0);
    }

    function _getPaymentPriceInWei(address paymentToken) internal view override returns (uint256) {
        address _oracle = paymentOracle[paymentToken];
        // slither-disable-next-line unused-return
        (, int256 paymentPrice,,,) = AggregatorV3Interface(_oracle).latestRoundData();
        // slither-disable-next-line unused-return
        (, int256 ethUSDPrice,,,) = AggregatorV3Interface(ethUsdOracle).latestRoundData();
        // adjust values to align decimals
        uint8 paymentPriceDecimals = AggregatorV3Interface(_oracle).decimals();
        uint8 ethUSDPriceDecimals = AggregatorV3Interface(ethUsdOracle).decimals();
        if (paymentPriceDecimals > ethUSDPriceDecimals) {
            ethUSDPrice = ethUSDPrice * int256(10 ** (paymentPriceDecimals - ethUSDPriceDecimals));
        } else if (paymentPriceDecimals < ethUSDPriceDecimals) {
            paymentPrice = paymentPrice * int256(10 ** (ethUSDPriceDecimals - paymentPriceDecimals));
        }
        // compute payment price in wei
        uint256 paymentPriceInWei = PrbMath.mulDiv(uint256(paymentPrice), 1 ether, uint256(ethUSDPrice));
        return uint256(paymentPriceInWei);
    }
}
