// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "solady/auth/Ownable.sol";
import "openzeppelin/utils/Address.sol";

/// @notice
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/Router.sol)
contract Router is Ownable {
    error LengthMismatch();
    error UnauthorizedCall();

    mapping(bytes32 => bool) private _authorizedCalls;

    function authorizeCall(address target, bytes4 method, bool allow) external onlyOwner {
        _authorizedCalls[bytes32(abi.encodePacked(target, method))] = allow;
    }

    function isAuthorizedCall(address target, bytes4 method) public view returns (bool) {
        return _authorizedCalls[bytes32(abi.encodePacked(target, method))];
    }

    function execute(address[] calldata targets, bytes[] calldata calldatas) public payable {
        uint256 numCalls = calldatas.length;
        if (targets.length != numCalls) revert LengthMismatch();

        for (uint256 i = 0; i < numCalls;) {
            if (!isAuthorizedCall(targets[i], bytes4(calldatas[i]))) revert UnauthorizedCall();

            Address.functionCall(targets[i], calldatas[i]);

            unchecked {
                i++;
            }
        }
    }
}
