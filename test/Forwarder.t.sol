// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Forwarder} from "../src/metatx/Forwarder.sol";
import {OrderFees, IOrderFees} from "../src/issuer/OrderFees.sol";
import "./utils/mocks/MockBridgedERC20.sol";
import "../src/issuer/BuyOrderIssuer.sol";
import "solady-test/utils/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/SigUtils.sol";
import "./utils/MetaTxProcessor.sol";

contract ForwarderTest is Test {
    Forwarder forwarder;
    BuyOrderIssuer issuer;
    OrderFees orderFees;
    MockERC20 paymentToken;
    BridgedERC20 token;
    MetaProcessor metaProcessor;

    SigUtils sigUtils;
    OrderProcessor.OrderRequest dummyOrder;

    bytes32 constant salt = 0x0000000000000000000000000000000000000000000000000000000000000001;

    uint256 userPrivateKey;
    uint256 relayerPrivateKey;
    uint256 ownerPrivateKey;
    address user;
    address relayer;
    address owner;

    address constant treasury = address(4);
    address constant operator = address(3);

    function setUp() public {
        userPrivateKey = 0x01;
        relayerPrivateKey = 0x02;
        ownerPrivateKey = 0x03;
        relayer = vm.addr(relayerPrivateKey);
        user = vm.addr(userPrivateKey);
        owner = vm.addr(ownerPrivateKey);

        token = new MockBridgedERC20();
        paymentToken = new MockERC20("Money", "$", 6);
        orderFees = new OrderFees(address(this), 1 ether, 0.005 ether);
        BuyOrderIssuer issuerImpl = new BuyOrderIssuer();

        issuer = BuyOrderIssuer(
            address(
                new ERC1967Proxy(address(issuerImpl), abi.encodeCall(
                    issuerImpl.initialize, 
                    (address(this), 
                    treasury, 
                    orderFees)
                ))
            )
        );

        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.MINTER_ROLE(), address(issuer));

        issuer.grantRole(issuer.PAYMENTTOKEN_ROLE(), address(paymentToken));
        issuer.grantRole(issuer.ASSETTOKEN_ROLE(), address(token));
        issuer.grantRole(issuer.OPERATOR_ROLE(), operator);
        vm.prank(owner); // we set an owner to deploy forwarder
        forwarder = new Forwarder(relayer, 3600); // 1 hour for pruce recency threshold
        sigUtils = new SigUtils(forwarder.DOMAIN_SEPARATOR());
        metaProcessor = new MetaProcessor(sigUtils);
    }

    function test_owner() public {
        assertEq(forwarder.owner(), owner);
    }

    function test_addProcessor() public {
        vm.expectRevert();
        forwarder.addProcessor(address(issuer));
        vm.prank(owner);
        forwarder.addProcessor(address(issuer));
    }

    function test_removeProcessor() public {
        vm.expectRevert();
        forwarder.removeProcessor(address(issuer));
        vm.prank(owner);
        forwarder.removeProcessor(address(issuer));
    }

    function testRequestOrderThroughForwarder(uint256 quantityIn) public {
        OrderProcessor.OrderRequest memory order = OrderProcessor.OrderRequest({
            recipient: user,
            assetToken: address(token), // Assuming you have token declared
            paymentToken: address(paymentToken),
            quantityIn: quantityIn
        });

        bytes4 functionSignature = bytes4(keccak256("requestOrder(OrderProcessor.OrderRequest,bytes32)"));
        bytes memory data = abi.encodeWithSelector(functionSignature, order, salt);
        uint256 nonce = 0; // set to the correct nonce for the user

        // prepare MetaTransaction
        bytes32 hashToSign = metaProcessor.prepareMetaTransaction(address(issuer), address(paymentToken), data, nonce);
        // user sign transaction
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, hashToSign);

        // the signed transaction could be sent to a relayer. The relayer will submit the transaction to the Forwarder

        // Create MetaTransaction struct with signature
        SigUtils.MetaTransaction memory metaTx = SigUtils.MetaTransaction({
            user: user,
            to: address(issuer),
            paymentToken: address(paymentToken),
            data: data,
            nonce: nonce,
            v: v,
            r: r,
            s: s
        });
    }
}
