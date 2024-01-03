// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {IOrderProcessor} from "../orders/IOrderProcessor.sol";

/// @notice Contract interface for paying gas fees for users and forwarding meta transactions to OrderProcessor contracts.
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/forwarder/IForwarder.sol)
interface IForwarder {
    struct ForwardRequest {
        address user; // The address of the user initiating the meta-transaction.
        address to; // The address of the target contract (e.g., OrderProcessor)
            // to which the meta-transaction should be forwarded.
        bytes data; // Encoded function call that the user wants to execute
            // through the meta-transaction.
        uint64 deadline; // The time by which the meta-transaction must be mined.
        uint256 nonce; // A nonce to prevent replay attacks. It must be unique
            // for each meta-transaction made by the user.
        bytes signature; // ECDSA signature of the user authorizing the meta-transaction.
    }

    struct OrderForwardRequest {
        address user;
        address to;
        IOrderProcessor.Order order;
        uint256 deadline;
        uint256 nonce;
        bytes signature;
    }

    struct CancelForwardRequest {
        address user;
        address to;
        uint256 orderId;
        uint256 deadline;
        uint256 nonce;
        bytes signature;
    }

    /// @notice The fee rate in basis points (1 basis point = 0.01%) for paying gas fees in tokens.
    function feeBps() external view returns (uint16);

    /// @notice Gas cost estimate added to cover oder cancellations.
    function cancellationGasCost() external view returns (uint256);

    /// @notice The mapping of relayer addresses authorize to send meta transactions.
    function isRelayer(address relayer) external view returns (bool);

    /// @notice The mapping of order IDs to signers used for order cancellation protection.
    function orderSigner(uint256 orderId) external view returns (address);

    /// @notice EIP-712 compliant order forward request hash function.
    function orderForwardRequestHash(OrderForwardRequest calldata metaTx) external pure returns (bytes32);

    /// @notice EIP-712 compliant cancel forward request hash function.
    function cancelForwardRequestHash(CancelForwardRequest calldata metaTx) external pure returns (bytes32);

    /**
     * @notice Forwards a meta transaction to an BuyOrder contract.
     * @dev Validates the meta transaction signature, then forwards the call to the target OrderProcessor.
     * The relayer's address is used for EIP-712 compliant signature verification.
     * This function should only be called by the authorized relayer.
     * @param metaTx The meta transaction containing the user address, target contract, encoded function call data,
     * deadline, nonce, payment token oracle price, and the signature components (v, r, s).
     * @return The return data of the forwarded function call.
     */
    function forwardRequestBuyOrder(OrderForwardRequest calldata metaTx) external returns (uint256);

    /**
     * @notice Forwards a meta transaction to cancel an Order to OrderProcessor contract.
     * @dev Validates the meta transaction signature, then forwards the call to the target OrderProcessor.
     * The relayer's address is used for EIP-712 compliant signature verification.
     * This function should only be called by the authorized relayer.
     * @param metaTx The meta transaction containing the user address, target contract, encoded function call data,
     * deadline, nonce, payment token oracle price, and the signature components (v, r, s).
     */
    function forwardRequestCancel(CancelForwardRequest calldata metaTx) external;

    /**
     * @notice Forwards a meta transaction to an SellOrder contract.
     * @dev Validates the meta transaction signature, then forwards the call to the target OrderProcessor.
     * The relayer's address is used for EIP-712 compliant signature verification.
     * This function should only be called by the authorized relayer.
     * @param metaTx The meta transaction containing the user address, target contract, encoded function call data,
     * deadline, nonce, payment token oracle price, and the signature components (v, r, s).
     * @return The return data of the forwarded function call.
     */
    function forwardRequestSellOrder(OrderForwardRequest calldata metaTx) external returns (uint256);
}
