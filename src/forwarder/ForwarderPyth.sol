// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {Forwarder} from "./Forwarder.sol";
import {IPyth} from "pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "pyth-sdk-solidity/PythStructs.sol";
import "prb-math/Common.sol" as PrbMath;

/// @notice Forwarder using pyth oracles
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/forwarder/ForwarderPyth.sol)
contract ForwarderPyth is Forwarder {
    /// ------------------------------- Types -------------------------------

    event PythContractSet(address indexed pyth);
    event EthUsdOracleSet(bytes32 indexed oracleId);
    event PaymentOracleSet(address indexed paymentToken, bytes32 indexed oracleId);

    /// ------------------------------- Storage -------------------------------

    IPyth public pyth;

    bytes32 public ethUsdOracleId;

    mapping(address => bytes32) public paymentOracleId;

    /// ------------------------------- Initialization -------------------------------

    /// @notice Constructs the Forwarder contract.
    /// @dev Initializes the domain separator used for EIP-712 compliant signature verification.
    constructor(address pythContract, bytes32 ethUsdPythId, uint256 initialSellOrderGasCost)
        Forwarder(initialSellOrderGasCost)
    {
        pyth = IPyth(pythContract);
        ethUsdOracleId = ethUsdPythId;
    }

    /// ------------------------------- Administration -------------------------------

    /**
     * @dev set pyth contract address
     * @param pythContract pyth contract address
     */
    function setPythContract(address pythContract) external onlyOwner {
        pyth = IPyth(pythContract);
        emit PythContractSet(pythContract);
    }

    /**
     * @dev add oracle for eth in usd
     * @param id pyth oracle id
     */
    function setEthUsdOracle(bytes32 id) external onlyOwner {
        ethUsdOracleId = id;
        emit EthUsdOracleSet(id);
    }

    /**
     * @dev add oracle for a payment token
     * @param paymentToken asset to add oracle
     * @param oracle pyth oracle id
     */
    function setPaymentOracle(address paymentToken, bytes32 oracle) external onlyOwner {
        paymentOracleId[paymentToken] = oracle;
        emit PaymentOracleSet(paymentToken, oracle);
    }

    /// ------------------------------- Oracle Usage -------------------------------

    function isSupportedToken(address token) public view override returns (bool) {
        return paymentOracleId[token] != bytes32(0);
    }

    function _getPaymentPriceInWei(address paymentToken) internal view override returns (uint256) {
        bytes32 _oracle = paymentOracleId[paymentToken];
        PythStructs.Price memory paymentPriceInfo = pyth.getPriceUnsafe(_oracle);
        int256 paymentPrice = paymentPriceInfo.price;
        PythStructs.Price memory ethUSDPriceInfo = pyth.getPriceUnsafe(ethUsdOracleId);
        int256 ethUSDPrice = ethUSDPriceInfo.price;
        // adjust values to align decimals
        if (paymentPriceInfo.expo > ethUSDPriceInfo.expo) {
            ethUSDPrice = ethUSDPrice * int256(10 ** uint32(paymentPriceInfo.expo - ethUSDPriceInfo.expo));
        } else if (paymentPriceInfo.expo < ethUSDPriceInfo.expo) {
            paymentPrice = paymentPrice * int256(10 ** uint32(ethUSDPriceInfo.expo - paymentPriceInfo.expo));
        }
        // compute payment price in wei
        return PrbMath.mulDiv(uint256(paymentPrice), 1 ether, uint256(ethUSDPrice));
    }
}
