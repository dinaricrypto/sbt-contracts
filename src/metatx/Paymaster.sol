// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseRelayRecipient} from "gsnV3/contracts/src/BaseRelayRecipient.sol";
import {IOrderProcessor} from "../issuer/IOrderProcessor.sol";
import "gsnV3/contracts/src/utils/GsnTypes.sol";
import {IPaymaster} from "gsnV3/contracts/src/interfaces/IPaymaster.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @notice Contract for paying gas fees for users
contract Paymaster is IPaymaster, Ownable {
    mapping(address => bool) public isUserOptedIn;
    IOrderProcessor public orderProcessor;
    address public relayHub;
    address public trustedForwarder;

    GasAndDataLimits public gasAndDataLimits;

    constructor(address orderProcessorAddress, address relayHubAddress, address _trustedForwarder) {
        orderProcessor = IOrderProcessor(orderProcessorAddress);
        relayHub = relayHubAddress;
        trustedForwarder = _trustedForwarder;
    }

    function setUserOptInStatus(bool optIn) external {
        isUserOptedIn[msg.sender] = optIn;
    }

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

    function getGasAndDataLimits() external view override returns (GasAndDataLimits memory limits) {
        return gasAndDataLimits;
    }

    function getHubAddr() external view override returns (address) {
        return relayHub;
    }

    function getRelayHubDeposit() external view override returns (uint256) {
        // Return the deposit balance of the Paymaster from the RelayHub contract
    }

    function preRelayedCall(
        GsnTypes.RelayRequest calldata relayRequest,
        bytes calldata signature,
        bytes calldata approvalData,
        uint256 maxPossibleGas
    ) external view override returns (bytes memory context, bool rejectOnRecipientRevert) {
        if (userHasOptedInOrSigned(relayRequest.request.from)) {
            // Pass the amount or any other relevant data through the context
            // For example, let's assume that the approvalData contains the amount
            return (approvalData, false); // allow the call to proceed
        } else {
            revert("User did not opt-in for sponsorship");
        }
    }

    function postRelayedCall(
        bytes calldata context,
        bool success,
        uint256 gasUseWithoutPost,
        GsnTypes.RelayData calldata relayData
    ) external override {
        if (success) {
            // Extract data from the context passed from preRelayedCall and execute the order
            uint256 amount = abi.decode(context, (uint256));
            executeRequestOrder(amount);
        }
    }

    function executeRequestOrder(uint256 amount) internal {
        IOrderProcessor.OrderRequest memory orderRequest = IOrderProcessor.OrderRequest({
            recipient: _msgSender(),
            assetToken: address(0), // This should be properly set
            paymentToken: address(0), // This should be properly set
            quantityIn: amount
        });

        orderProcessor.requestOrder(orderRequest);
    }

    // function _msgSender() internal override  view returns (address) {
    //     if (msg.sender == trustedForwarder) {
    //         return address(bytes20(msg.data[msg.data.length - 20: msg.data.length]));
    //     }
    //     return msg.sender;
    // }

    function userHasOptedInOrSigned(address user) internal view returns (bool) {
        // Implement logic here to check if the user has opted in or signed
    }

    function versionPaymaster() external view override returns (string memory) {
        return "1.0";
    }
}
