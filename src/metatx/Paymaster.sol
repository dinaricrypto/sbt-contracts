// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseRelayRecipient} from "gsnV3/contracts/src/BaseRelayRecipient.sol";
import {IOrderProcessor} from "../issuer/IOrderProcessor.sol";
import "gsnV3/contracts/src/utils/GsnTypes.sol";
import {IPaymaster} from "gsnV3/contracts/src/interfaces/IPaymaster.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @notice Contract for paying gas fees for users
contract Paymaster is IPaymaster, Ownable {
    // Addresses
    address public relayHub;
    address public trustedForwarder;
    IOrderProcessor public orderProcessor;

    // Struct
    GasAndDataLimits public gasAndDataLimits;

    // Constants
    string private constant PERMISSION_TYPE = "Permission(address user,uint256 nonce)";
    string private constant EIP712_DOMAIN =
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";

    // Domain separator
    bytes32 private domainSeparator;

    // Typehashes
    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(abi.encodePacked(EIP712_DOMAIN));
    bytes32 private constant PERMISSION_TYPEHASH = keccak256(abi.encodePacked(PERMISSION_TYPE));

    // Mappings
    mapping(address => uint256) public userNonces;

    // errors
    error UserHasNotSigned(string reason);
    error InvalidNonce();

    // events
    event OrderRequested(
        address indexed recipient, address assetToken, address paymentToken, uint256 quantityIn, bytes32 orderId
    );
    event OrderCancelled(address indexed recipient, bytes32 orderId);

    constructor(address orderProcessorAddress, address relayHubAddress, address _trustedForwarder) {
        orderProcessor = IOrderProcessor(orderProcessorAddress);
        relayHub = relayHubAddress;
        trustedForwarder = _trustedForwarder;
        domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("Paymaster"),
                keccak256("1"), // version
                getChainId(),
                address(this)
            )
        );
    }

    /**
     * @param acceptanceBudget Maximum amount of gas the paymaster is willing to pay for the transaction
     * @param preRelayedCallGasLimit Maximum amount of gas that can be used by the preRelayedCall function
     * @param postRelayedCallGasLimit Maximum amount of gas that can be used by the postRelayedCall function
     * @param calldataSizeLimit Maximum size of the calldata that the paymaster is willing to accept
     */
    function setGasAndDataLimits(
        uint256 acceptanceBudget,
        uint256 preRelayedCallGasLimit,
        uint256 postRelayedCallGasLimit,
        uint256 calldataSizeLimit
    ) external onlyOwner {
        gasAndDataLimits = GasAndDataLimits({
            acceptanceBudget: acceptanceBudget,
            preRelayedCallGasLimit: preRelayedCallGasLimit,
            postRelayedCallGasLimit: postRelayedCallGasLimit,
            calldataSizeLimit: calldataSizeLimit
        });
    }

    /**
     * @dev Returns the current gas and data limits set by the Paymaster.
     * @return limits A struct containing the acceptance budget,
     * gas limits for preRelayedCall and postRelayedCall, and calldata size limit.
     */
    function getGasAndDataLimits() external view override returns (GasAndDataLimits memory limits) {
        return gasAndDataLimits;
    }

    /**
     * @dev Returns the address of the RelayHub contract that this Paymaster is using.
     * @return The address of the RelayHub contract.
     */
    function getHubAddr() external view override returns (address) {
        return relayHub;
    }

    /**
     * @dev Returns the deposit balance of the Paymaster in the RelayHub contract.
     * This function should interact with the RelayHub contract to return the deposit balance of the Paymaster.
     * @return The deposit balance of the Paymaster in the RelayHub contract.
     */
    function getRelayHubDeposit() external view override returns (uint256) {
        // Return the deposit balance of the Paymaster from the RelayHub contract
    }

    /**
     * @param relayRequest The relay request containing details of the relayed call.
     * @param signature The signature of the user who is requesting the relayed call.
     * @param approvalData Data that can be used for off-chain approvals or additional information.
     * @param maxPossibleGas The maximum amount of gas that can be used for executing the relayed call.
     * @return context The data to be passed to the postRelayedCall function.
     * @return rejectOnRecipientRevert Boolean flag indicating whether
     * the relayed call should be rejected if the recipient reverts.
     */
    function preRelayedCall(
        GsnTypes.RelayRequest calldata relayRequest,
        bytes calldata signature,
        bytes calldata approvalData,
        uint256 maxPossibleGas
    ) external view returns (bytes memory context, bool rejectOnRecipientRevert) {
        address user = relayRequest.request.from;
        // Extract v, r, s from signature
        (bytes32 r, bytes32 s, uint8 v) = abi.decode(signature, (bytes32, bytes32, uint8));
        // Logic to check if user has signed, assuming approvalData is correctly encoded
        if (userHasSigned(user, v, r, s, approvalData)) {
            // Pass data through the context to postRelayedCall if needed
            // For example, you can pass the data necessary for executing the order
            return (approvalData, true);
        } else {
            revert UserHasNotSigned("User has not provided a valid signature.");
        }
    }

    /**
     * @param context Data passed from the preRelayedCall function
     * @param success A boolean indicating whether the relayed call was successful.
     * @param gasUseWithoutPost The amount of gas used by the relayed call excluding the gas used by postRelayedCall.
     * @param relayData Additional data about the relay request.
     */
    function postRelayedCall(
        bytes calldata context,
        bool success,
        uint256 gasUseWithoutPost,
        GsnTypes.RelayData calldata relayData
    ) external {
        if (success) {
            // Decode the context to get the action (create or cancel) and parameters for the order
            (string memory action, address assetToken, address paymentToken, uint256 quantityIn, bytes32 orderId) =
                abi.decode(context, (string, address, address, uint256, bytes32));

            //todo estimate gas used by postRelayedCall approve fees token and transfer to paymaster
            uint256 gasPrice = tx.gasprice;
            uint256 totalGasUsed = gasUseWithoutPost * gasPrice;

            if (keccak256(bytes(action)) == keccak256(bytes("create"))) {
                // Construct the OrderRequest struct
                IOrderProcessor.OrderRequest memory orderRequest = IOrderProcessor.OrderRequest({
                    recipient: _msgSender(),
                    assetToken: assetToken,
                    paymentToken: paymentToken,
                    quantityIn: quantityIn
                });

                // todo Check if the order is too small to pay fees

                // Call the requestOrder function through the IOrderProcessor interface
                bytes32 newOrderId = orderProcessor.requestOrder(orderRequest);
                emit OrderRequested(_msgSender(), assetToken, paymentToken, quantityIn, newOrderId);

                // Do something with the newOrderId if needed
            } else if (keccak256(bytes(action)) == keccak256(bytes("cancel"))) {
                // Call the requestCancel function through the IOrderProcessor interface to cancel the order
                orderProcessor.requestCancel(orderId);
                emit OrderCancelled(_msgSender(), orderId);
            }
        }
    }

    /**
     * @dev check if user has signed the data.
     * @param user The address of the user that should have signed the data.
     * @param v The recovery ID, a part of the signature (27 or 28).
     * @param r The r value of the signature.
     * @param s The s value of the signature.
     * @param approvalData The additional data that needs to be checked against the signature.
     * @return A boolean indicating whether the signature is valid and from the provided user address.
     */
    function userHasSigned(address user, uint8 v, bytes32 r, bytes32 s, bytes memory approvalData)
        internal
        view
        returns (bool)
    {
        uint256 nonce;

        // Extract nonce from approvalData or any other data if necessary
        assembly {
            nonce := mload(add(approvalData, 32))
        }

        // Ensure the nonce is valid
        if (nonce != userNonces[user]) {
            revert InvalidNonce();
        }

        bytes32 structHash = keccak256(abi.encode(PERMISSION_TYPEHASH, user, nonce));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        return ecrecover(digest, v, r, s) == user;
    }

    function getChainId() internal view returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }

    function versionPaymaster() external pure override returns (string memory) {
        return "1.0";
    }
}
