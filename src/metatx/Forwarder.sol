// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {PriceAttestationConsumer} from "./PriceAttestationConsumer.sol";

/// @title Forwarder
/// @notice Contract for paying gas fees for users and forwarding meta transactions to OrderProcessor contracts.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/issuer/OrderProcessor.sol)
contract Forwarder is Ownable, PriceAttestationConsumer {
    address public relayer;

    mapping(address => bool) public validProcessors;
    mapping(address => uint256) public nonces;

    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant FUNCTION_CALL_TYPEHASH =
        keccak256("FunctionCall(address user,address to,bytes data,uint256 nonce)");

    bytes32 public DOMAIN_SEPARATOR;

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
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("Forwarder")), keccak256(bytes("1")), chainId, address(this))
        );
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
        uint256 gasStart = gasleft(); // Get the remaining gas at the beginning of execution
        if (!validProcessors[metaTx.to]) revert IsNotValidProcessor();
        if (nonces[metaTx.user] != metaTx.nonce) revert InvalidNonces();
        if (oraclePrice.token != metaTx.paymentToken) revert WrongTokenPrice();
        _verifyPriceAttestation(oraclePrice);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        FUNCTION_CALL_TYPEHASH,
                        metaTx.user,
                        metaTx.to,
                        keccak256(metaTx.data),
                        metaTx.nonce,
                        metaTx.v,
                        metaTx.r,
                        metaTx.s
                    )
                )
            )
        );

        address signer = ecrecover(digest, metaTx.v, metaTx.r, metaTx.s);
        if (signer != metaTx.user) revert InvalidSigner();

        nonces[metaTx.user]++; // increment nonce after successful forward

        (bool success,) = metaTx.to.call(metaTx.data);
        require(success, "Forwarded call failed");

        _handlePayment(metaTx.user, metaTx.paymentToken, oraclePrice.price, gasStart);
    }

    /**
     * @notice This function should use an off-chain service to provide pricing information.
     * @dev Converts the gas used by the transaction into the equivalent amount in the user's chosen ERC20 token.
     * @param gasUsed The total gas used by the transaction.
     * @param token The address of the ERC20 token in which the user wants to make the payment.
     * @return amount The equivalent amount in the chosen ERC20 token.
     */
    function convertGasToTokenAmount(uint256 gasUsed, address token) internal pure returns (uint256 amount) {
        // Conversion logic here, using an off-chain service for pricing information.
        return amount;
    }

    /**
     * @dev Handles the payment of transaction fees in the specified ERC20 token.
     * Calculates the gas used by the transaction and converts it to an equivalent amount ,
     * of the specified ERC20 token.
     * Then, transfers the calculated amount of ERC20 tokens from the user's address to the relayer's
     * address as a payment for transaction fees.
     *
     * Note: The conversion rate between gas and the ERC20 token should be determined ,
     * by an off-chain oracle or pricing feed.
     *
     * @param user The address of the user who is paying the transaction fees.
     * @param paymentToken The address of the ERC20 token in which the transaction fees are paid.
     * @param paymentTokenPrice The price of the payment token
     * @param gasStart The amount of gas left at the start of the transaction execution.
     */
    function _handlePayment(address user, address paymentToken, uint256 paymentTokenPrice, uint256 gasStart) internal {
        // Calculate the total gas used by this transaction
        uint256 gasUsed = gasStart - gasleft();

        // TODO: Convert the total gas used to the equivalent payment in the user's chosen
        // ERC20 token using pricing feeds or oracle.
        // For this example, let's assume that a function `convertGasToTokenAmount` exists that performs this conversion
        uint256 paymentAmount = convertGasToTokenAmount(gasUsed, paymentToken);

        // Transfer the payment for gas fees
        IERC20(paymentToken).transferFrom(user, relayer, paymentAmount);
    }
}
