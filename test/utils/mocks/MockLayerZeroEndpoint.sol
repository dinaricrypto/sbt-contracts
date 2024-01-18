// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

contract MockLayerZeroEndpoint {
    address public delegate;

    function setDelegate(address _delegate) external {
        delegate = _delegate;
    }
}
