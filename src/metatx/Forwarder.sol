// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
/// @title Forwarder
/// @notice Contract for paying gas fees for users and forwarding meta transactions to OrderProcessor contracts.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/issuer/OrderProcessor.sol)

contract Forwarder is Ownable {
    address public relayer;

    mapping(address => bool) public validProcessors;
    mapping(address => uint256) public nonces;

    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant FUNCTION_CALL_TYPEHASH =
        keccak256("FunctionCall(address user,address to,bytes data,uint256 nonce)");

    bytes32 public DOMAIN_SEPARATOR;

    error UserNotRelayer();
    error IsNotValidProcessor();
    error InvalidNonces();
    error InvalidSigner();

    modifier onlyRelayer() {
        if (msg.sender != relayer) {
            revert UserNotRelayer();
        }
        _;
    }

    /// @notice Constructs the Forwarder contract.
    /// @dev Initializes the domain separator used for EIP-712 compliant signature verification.
    /// @param _relayer The address of the relayer authorized to submit meta transactions.
    constructor(address _relayer) {
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
    /// @param user The address of the user that signed the MetaTx. This address is used to validate the signature
    /// and ensure that the transaction is being initiated by the intended user.
    /// @param to The address of the OrderProcessor contract where the transaction should be forwarded to.
    /// @param data The encoded function call that the user would like to execute.
    /// @param nonce The nonce for the user's account. This is used to prevent replay attacks.
    /// @param v ECDSA signature parameter v.
    /// @param r ECDSA signature parameter r.
    /// @param s ECDSA signature parameter s.
    function forwardFunctionCall(
        address user,
        address paymentToken,
        address to,
        bytes calldata data,
        uint256 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyRelayer {
        uint256 gasStart = gasleft(); // Get the remaining gas at the beginning of execution
        if (!validProcessors[to]) revert IsNotValidProcessor();
        if (nonces[user] != nonce) revert InvalidNonces();

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(FUNCTION_CALL_TYPEHASH, user, to, keccak256(data), nonce, v, r, s))
            )
        );

        address signer = ecrecover(digest, v, r, s);
        if (signer != user) revert InvalidSigner();

        nonces[user]++; // increment nonce after successful forward

        (bool success,) = to.call(data);
        require(success, "Forwarded call failed");

        _handlePayment(user, paymentToken, gasStart);
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

    function _handlePayment(address user, address paymentToken, uint256 gasStart) internal {
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
