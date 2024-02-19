// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {ITokenManagerType} from "./ITokenManagerType.sol";

interface IInterchainTokenService {
    function deployTokenManager(
        bytes32 salt,
        string calldata destinationChain,
        ITokenManagerType.TokenManagerType tokenManagerType,
        bytes calldata params,
        uint256 gasValue
    ) external payable returns (bytes32);
}
