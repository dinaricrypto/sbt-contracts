// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {PriceAttestationConsumer} from "./PriceAttestationConsumer.sol";

/// @title Forwarder
/// @notice Contract for paying gas fees for users and forwarding meta transactions to OrderProcessor contracts.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/issuer/OrderProcessor.sol)
contract Forwarder is Ownable, PriceAttestationConsumer, EIP712("Forwarder", "1") {
    address public relayer;

    mapping(address => bool) public validProcessors;
    mapping(address => uint256) public nonces;

    bytes32 public constant FUNCTION_CALL_TYPEHASH =
        keccak256("FunctionCall(address user,address to,bytes data,uint256 nonce)");

    struct MetaTransaction {
        address user; // The address of the user initiating the meta-transaction.
        address to; // The address of the target contract (e.g., OrderProcessor)
            // to which the meta-transaction should be forwarded.
        address paymentToken; // The address of the ERC20 token that the user wants to
            // use for paying the transaction fees.
        bytes data; // Encoded function call that the user wants to execute
            // through the meta-transaction.
        uint256 nonce; // A nonce to prevent replay attacks. It must be unique
            // for each meta-transaction made by the user.
        uint8 v; // ECDSA signature parameter v.
        bytes32 r; // ECDSA signature parameter r.
        bytes32 s; // ECDSA signature parameter s.
    }

    error UserNotRelayer();
    error IsNotValidProcessor();
    error InvalidNonces();
    error InvalidSigner();
    error WrongTokenPrice();

    modifier onlyRelayer() {
        if (msg.sender != relayer) {
            revert UserNotRelayer();
        }
        _;
    }

    /// @notice Constructs the Forwarder contract.
    /// @dev Initializes the domain separator used for EIP-712 compliant signature verification.
    /// @param _relayer The address of the relayer authorized to submit meta transactions.
    constructor(address _relayer, uint256 _priceRecencyThreshold) PriceAttestationConsumer(_priceRecencyThreshold) {
        relayer = _relayer;
    }

    /// @notice Adds an OrderProcessor contract address as a valid processor.
    /// @dev Only the owner can add an OrderProcessor.
    /// @param processor The address of the OrderProcessor contract.
    function addProcessor(address processor) external onlyOwner {
        validProcessors[processor] = true;
    }

    /// @notice Removes an OrderProcessor contract address from the set of valid processors.
    /// @dev Only the owner can remove an OrderProcessor.
    /// @param processor The address of the OrderProcessor contract.
    function removeProcessor(address processor) external onlyOwner {
        validProcessors[processor] = false;
    }

    /// @notice Forwards a meta transaction to an OrderProcessor contract.
    /// @dev Validates the meta transaction signature, then forwards the call to the target OrderProcessor.
    /// The relayer's address is used for EIP-712 compliant signature verification.
    /// This function should only be called by the authorized relayer.

    function forwardFunctionCall(MetaTransaction memory metaTx, PriceAttestation memory oraclePrice)
        external
        onlyRelayer
    {
        uint256 gasStart = gasleft();
        if (!validProcessors[metaTx.to]) revert IsNotValidProcessor();
        if (nonces[metaTx.user] != metaTx.nonce) revert InvalidNonces();
        if (oraclePrice.token != metaTx.paymentToken) revert WrongTokenPrice();
        _verifyPriceAttestation(oraclePrice);

        bytes32 structHash =
            keccak256(abi.encode(FUNCTION_CALL_TYPEHASH, metaTx.user, metaTx.to, keccak256(metaTx.data), metaTx.nonce));

        bytes32 digest = _hashTypedDataV4(structHash);

        address signer = ecrecover(digest, metaTx.v, metaTx.r, metaTx.s);
        if (signer != metaTx.user) revert InvalidSigner();

        nonces[metaTx.user]++;

        (bool success,) = metaTx.to.call(metaTx.data);
        require(success, "Forwarded call failed");

        _handlePayment(metaTx.user, metaTx.paymentToken, oraclePrice.price, gasStart);
    }

    /**
     * @notice Converts the gas used by the transaction into the equivalent amount in the user's chosen ERC20 token.
     * @param gasUsed The total gas used by the transaction.
     * @param paymentTokenPrice The price of the payment token in wei.
     * @return amount The equivalent amount in the chosen ERC20 token.
     */
    function convertGasToTokenAmount(uint256 gasUsed, uint256 paymentTokenPrice)
        internal
        view
        returns (uint256 amount)
    {
        uint256 gasCostInWei = gasUsed * tx.gasprice;
        // Assuming paymentTokenPrice is the price of 1 token in wei.
        return gasCostInWei / paymentTokenPrice;
    }

    /**
     * @dev Handles the payment of transaction fees in the specified ERC20 token.
     * @param user The address of the user who is paying the transaction fees.
     * @param paymentToken The address of the ERC20 token in which the transaction fees are paid.
     * @param paymentTokenPrice The price of the payment token in wei.
     * @param gasStart The amount of gas left at the start of the transaction execution.
     */
    function _handlePayment(address user, address paymentToken, uint256 paymentTokenPrice, uint256 gasStart) internal {
        // Calculate the total gas used by this transaction
        uint256 gasUsed = gasStart - gasleft();

        // Convert the total gas used to the equivalent payment in the user's chosen ERC20 token
        uint256 paymentAmount = convertGasToTokenAmount(gasUsed, paymentTokenPrice);

        // Transfer the payment for gas fees
        IERC20(paymentToken).transferFrom(user, relayer, paymentAmount);
    }
}
