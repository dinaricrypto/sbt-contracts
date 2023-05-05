// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./BridgedERC20.sol";

/// @notice .
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/BridgedTokenFactory.sol)
contract BridgedTokenFactory {
    event TokenDeployed(address indexed tokenAddress);

    function deployBridgedERC20(
        address owner,
        string memory name,
        string memory symbol,
        string memory disclosures,
        ITransferRestrictor transferRestrictor
    ) external returns (BridgedERC20 token) {
        token = new BridgedERC20(owner, name, symbol, disclosures, transferRestrictor);
        emit TokenDeployed(address(token));
    }
}
