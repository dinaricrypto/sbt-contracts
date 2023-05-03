// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/BridgedTokenFactory.sol";

contract BridgedTokenFactoryTest is Test {
    event TokenDeployed(address indexed tokenAddress);

    BridgedTokenFactory factory;

    function setUp() public {
        factory = new BridgedTokenFactory();
    }

    function testDeployToken() public {
        vm.expectEmit(false, false, false, false);
        emit TokenDeployed(address(3));
        factory.deployBridgedERC20(address(this), "name", "symbol", "disclosures", ITransferRestrictor(address(5)));
    }
}
