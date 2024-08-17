// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {IKintoWallet} from "kinto-contracts-helpers/interfaces/IKintoWallet.sol";
import {ISponsorPaymaster} from "kinto-contracts-helpers/interfaces/ISponsorPaymaster.sol";

import "kinto-contracts-helpers/EntryPointHelper.sol";

contract FundPaymaster is Script, EntryPointHelper {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address owner = vm.envAddress("OWNER");
        IEntryPoint _entryPoint = IEntryPoint(vm.envAddress("ENTRYPOINT"));
        ISponsorPaymaster _sponsorPaymaster = ISponsorPaymaster(vm.envAddress("SPONSOR_PAYMASTER"));

        console.log("deployer: %s", deployer);
        console.log("owner: %s", owner);

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        // Note: Fails due to SenderKYCRequired
        // _sponsorPaymaster.addDepositFor{value: 0.0007 ether}(owner);
        _handleOps(
            _entryPoint,
            abi.encodeCall(ISponsorPaymaster.addDepositFor, (owner)),
            owner,
            address(_sponsorPaymaster),
            0.01 ether,
            address(_sponsorPaymaster),
            deployerPrivateKey
        );

        vm.stopBroadcast();
    }
}
