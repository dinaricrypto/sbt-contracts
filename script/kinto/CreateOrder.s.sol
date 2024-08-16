// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/orders/OrderProcessor.sol";
import {IKintoWallet} from "kinto-contracts-helpers/interfaces/IKintoWallet.sol";
import {ISponsorPaymaster} from "kinto-contracts-helpers/interfaces/ISponsorPaymaster.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

import "kinto-contracts-helpers/EntryPointHelper.sol";

contract CreateOrder is Script, EntryPointHelper {
    function run() external {
        // load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_KEY_STAGE");
        address deployer = vm.addr(deployerPrivateKey);
        address owner = vm.envAddress("KINTO_WALLET");
        IEntryPoint _entryPoint = IEntryPoint(vm.envAddress("ENTRYPOINT"));
        ISponsorPaymaster _sponsorPaymaster = ISponsorPaymaster(vm.envAddress("SPONSOR_PAYMASTER"));
        OrderProcessor orderProcessor = OrderProcessor(vm.envAddress("ORDERPROCESSOR"));
        ERC20 usdc = ERC20(vm.envAddress("USDC"));

        console.log("deployer: %s", deployer);
        console.log("owner: %s", owner);

        address assetToken = 0xF5Afd69d9C7a867E47dE4147f6a031175ea05103;
        uint256 orderAmount = 10_000_000;

        IOrderProcessor.Order memory order = IOrderProcessor.Order({
            requestTimestamp: uint64(block.timestamp),
            recipient: owner,
            assetToken: assetToken,
            paymentToken: address(usdc),
            sell: false,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: orderAmount,
            price: 0,
            tif: IOrderProcessor.TIF.GTC
        });

        // send txs as deployer
        vm.startBroadcast(deployerPrivateKey);

        // approve
        _handleOps(
            _entryPoint,
            abi.encodeCall(ERC20.approve, (address(orderProcessor), orderAmount * 2)),
            owner,
            address(usdc),
            address(_sponsorPaymaster),
            deployerPrivateKey
        );

        _handleOps(
            _entryPoint,
            abi.encodeCall(OrderProcessor.createOrderStandardFees, (order)),
            owner,
            address(orderProcessor),
            address(_sponsorPaymaster),
            deployerPrivateKey
        );

        vm.stopBroadcast();
    }
}
