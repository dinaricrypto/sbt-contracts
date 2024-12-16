// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {IKintoAppRegistry} from "kinto-contracts-helpers/interfaces/IKintoAppRegistry.sol";
import {IKintoWallet} from "kinto-contracts-helpers/interfaces/IKintoWallet.sol";
import {ISponsorPaymaster} from "kinto-contracts-helpers/interfaces/ISponsorPaymaster.sol";

import "kinto-contracts-helpers/EntryPointHelper.sol";

contract AddToAppWhitelist is Script, EntryPointHelper {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY_STAGE");
        address deployer = vm.addr(deployerPrivateKey);
        address owner = vm.envAddress("KINTO_WALLET");
        IKintoAppRegistry _appRegistry = IKintoAppRegistry(vm.envAddress("APP_REGISTRY"));
        IEntryPoint _entryPoint = IEntryPoint(vm.envAddress("ENTRYPOINT"));
        ISponsorPaymaster _sponsorPaymaster = ISponsorPaymaster(vm.envAddress("SPONSOR_PAYMASTER"));

        console.log("deployer: %s", deployer);
        console.log("owner: %s", owner);

        address dinariAppParentContract = 0xB2eEc63Cdc175d6d07B8f69804C0Ab5F66aCC3cb;

        address[] memory contracts = new address[](11);
        contracts[0] = 0x7Fe7C97043e85155cbD0AF0A6D81F635e82b936b;
        contracts[1] = 0x80590a1151E769923908EA26E20bDe4b56a978c0;
        contracts[2] = 0xFEaAD9cB0644e93Dd7c16a51c5224EA5D10dC658;
        contracts[3] = 0x2B3D480792F019Fc3FFad3d6645BE90A32d34438;
        contracts[4] = 0x904409269c614c7699678Ead60d44A955Dc2FBF7;
        contracts[5] = 0x74CFc571d9184003824B9b565F2152c8E2c8b766;
        contracts[6] = 0x631Fd724AF29F2e68159A3984c524485a5881290;
        contracts[7] = 0x36ab8E5FCb5CE6dAd81Bf9E44EA24ACCcc7f32C5;
        contracts[8] = 0x3a0873bf19CE13Bc52d90311d93398f4c310F66B;
        contracts[9] = 0x765813601C803cF86561b230055DeE73801fFEfD;
        contracts[10] = 0xC06a5a697C02E67793cF9348fAf38bC35a543C93;

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        // _appRegistry.addAppContracts(dinariAppParentContract, contracts);
        _handleOps(
            _entryPoint,
            abi.encodeWithSelector(IKintoAppRegistry.addAppContracts.selector, dinariAppParentContract, contracts),
            owner,
            address(_appRegistry),
            address(_sponsorPaymaster),
            deployerPrivateKey
        );

        vm.stopBroadcast();
    }
}
