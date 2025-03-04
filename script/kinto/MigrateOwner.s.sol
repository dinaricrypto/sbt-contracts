// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.23;

// import "forge-std/Script.sol";
// import {TransferRestrictor} from "../../src/TransferRestrictor.sol";
// import {OrderProcessor} from "../../src/orders/OrderProcessor.sol";
// import {DividendDistribution} from "../../src/dividend/DividendDistribution.sol";
// import {DShareFactory} from "../../src/DShareFactory.sol";
// import {Vault} from "../../src/orders/Vault.sol";
// import {FulfillmentRouter} from "../../src/orders/FulfillmentRouter.sol";
// import {IKintoWallet} from "kinto-contracts-helpers/interfaces/IKintoWallet.sol";
// import {ISponsorPaymaster} from "kinto-contracts-helpers/interfaces/ISponsorPaymaster.sol";
// import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
// import {IAccessControlDefaultAdminRules} from
//     "openzeppelin-contracts/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
// import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
// import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

// import "kinto-contracts-helpers/EntryPointHelper.sol";

// // gives owner all permissions to TransferRestrictor and UsdPlus
// contract MigrateOwner is Script, EntryPointHelper {
//     struct Config {
//         TransferRestrictor transferRestrictor;
//         UpgradeableBeacon dShareBeacon;
//         UpgradeableBeacon wrappeddShareBeacon;
//         DShareFactory dShareFactory;
//         OrderProcessor orderProcessor;
//         Vault vault;
//         FulfillmentRouter fulfillmentRouter;
//         DividendDistribution dividendDistributor;
//     }

//     function run() external {
//         // load env variables
//         uint256 deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
//         address deployer = vm.addr(deployerPrivateKey);
//         address kintoWallet = vm.envAddress("KINTO_WALLET");
//         IEntryPoint _entryPoint = IEntryPoint(vm.envAddress("ENTRYPOINT"));
//         ISponsorPaymaster _sponsorPaymaster = ISponsorPaymaster(vm.envAddress("SPONSOR_PAYMASTER"));

//         Config memory cfg = Config({
//             transferRestrictor: TransferRestrictor(vm.envAddress("TRANSFERRESTRICTOR")),
//             dShareBeacon: UpgradeableBeacon(vm.envAddress("DSHAREBEACON")),
//             wrappeddShareBeacon: UpgradeableBeacon(vm.envAddress("WRAPPEDDSHAREBEACON")),
//             dShareFactory: DShareFactory(vm.envAddress("DSHAREFACTORY")),
//             orderProcessor: OrderProcessor(vm.envAddress("ORDERPROCESSOR")),
//             vault: Vault(vm.envAddress("VAULT")),
//             fulfillmentRouter: FulfillmentRouter(vm.envAddress("FULFILLMENTROUTER")),
//             dividendDistributor: DividendDistribution(vm.envAddress("DIVIDENDDISTRIBUTOR"))
//         });

//         console.log("deployer: %s", deployer);
//         console.log("kinto wallet: %s", kintoWallet);

//         // send txs as deployer
//         vm.startBroadcast(deployerPrivateKey);

//         // _handleOps(
//         //     _entryPoint,
//         //     abi.encodeCall(IAccessControlDefaultAdminRules.beginDefaultAdminTransfer, (newOwner)),
//         //     kintoWallet,
//         //     address(cfg.transferRestrictor),
//         //     address(_sponsorPaymaster),
//         //     deployerPrivateKey
//         // );

//         // _handleOps(
//         //     _entryPoint,
//         //     abi.encodeCall(Ownable.transferOwnership, (newOwner)),
//         //     kintoWallet,
//         //     address(cfg.dShareBeacon),
//         //     address(_sponsorPaymaster),
//         //     deployerPrivateKey
//         // );

//         // _handleOps(
//         //     _entryPoint,
//         //     abi.encodeCall(Ownable.transferOwnership, (newOwner)),
//         //     kintoWallet,
//         //     address(cfg.wrappeddShareBeacon),
//         //     address(_sponsorPaymaster),
//         //     deployerPrivateKey
//         // );

//         // _handleOps(
//         //     _entryPoint,
//         //     abi.encodeCall(Ownable.transferOwnership, (newOwner)),
//         //     kintoWallet,
//         //     address(cfg.dShareFactory),
//         //     address(_sponsorPaymaster),
//         //     deployerPrivateKey
//         // );

//         // _handleOps(
//         //     _entryPoint,
//         //     abi.encodeCall(Ownable2Step.transferOwnership, (newOwner)),
//         //     kintoWallet,
//         //     address(cfg.orderProcessor),
//         //     address(_sponsorPaymaster),
//         //     deployerPrivateKey
//         // );

//         // _handleOps(
//         //     _entryPoint,
//         //     abi.encodeCall(IAccessControlDefaultAdminRules.beginDefaultAdminTransfer, (newOwner)),
//         //     kintoWallet,
//         //     address(cfg.vault),
//         //     address(_sponsorPaymaster),
//         //     deployerPrivateKey
//         // );

//         // _handleOps(
//         //     _entryPoint,
//         //     abi.encodeCall(IAccessControlDefaultAdminRules.beginDefaultAdminTransfer, (newOwner)),
//         //     kintoWallet,
//         //     address(cfg.fulfillmentRouter),
//         //     address(_sponsorPaymaster),
//         //     deployerPrivateKey
//         // );

//         // _handleOps(
//         //     _entryPoint,
//         //     abi.encodeCall(IAccessControlDefaultAdminRules.beginDefaultAdminTransfer, (newOwner)),
//         //     kintoWallet,
//         //     address(cfg.dividendDistributor),
//         //     address(_sponsorPaymaster),
//         //     deployerPrivateKey
//         // );

//         cfg.transferRestrictor.acceptDefaultAdminTransfer();
//         cfg.orderProcessor.acceptOwnership();
//         cfg.vault.acceptDefaultAdminTransfer();
//         cfg.fulfillmentRouter.acceptDefaultAdminTransfer();
//         cfg.dividendDistributor.acceptDefaultAdminTransfer();

//         vm.stopBroadcast();
//     }
// }
