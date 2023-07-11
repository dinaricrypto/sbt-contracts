const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("EIP-712 Compliance Test", function() {
    let deployer, user1, treasury, orderFees, token, mockERC20;
    let BuyOrderIssuerFactory, OrderFeesFactory, TokenFactory, PaymentTokenFactory;
    let issuerImpl;

    before(async function() {
        [deployer, user1, treasury] = await ethers.getSigners();

        // Deploy mock payment token
        PaymentTokenFactory = await ethers.getContractFactory("mockToken");
        mockERC20 = await PaymentTokenFactory.deploy("Money", "$", 6);

        // Deploy mock asset token
        TokenFactory = await ethers.getContractFactory("mockToken");
        token = await TokenFactory.deploy("Token", "$", 6);

        // Deploy OrderFees contract
        OrderFeesFactory = await ethers.getContractFactory("OrderFees");
        orderFees = await OrderFeesFactory.deploy(
            deployer.address,
            ethers.parseEther("1"),
            ethers.parseEther("0.005")
        );


        // Deploy BuyOrderIssuer contract
        BuyOrderIssuerFactory = await ethers.getContractFactory("BuyOrderIssuer");
        issuerImpl = await upgrades.deployProxy(
            BuyOrderIssuerFactory,
            [deployer.address, treasury.address, await orderFees.getAddress()],
        );
    });

    it("Should correctly compute the EIP-712 typed data hash", async function() {
        const ORDERREQUEST_TYPE_HASH = ethers.id(
            "OrderRequest(bytes32 salt,address recipient,address assetToken,address paymentToken,uint256 quantityIn)"
        );
        const salt = ethers.id(
            "0x0000000000000000000000000000000000000000000000000000000000000001"
        );
        const recipient = user1.address;
        const assetToken = await token.getAddress();
        const paymentToken = await mockERC20.getAddress();
        const quantityIn = ethers.parseEther("1");
        const price = 0;

        const abi = new ethers.AbiCoder();

        const computeId = ethers.keccak256(
            abi.encode(
                ["bytes32", "bytes32", "address", "address", "address", "uint256"],
                [ORDERREQUEST_TYPE_HASH, salt, recipient, assetToken, paymentToken, quantityIn]
            )
        );

        const contractId = await issuerImpl.getOrderIdFromOrderRequest(
            {recipient, assetToken, paymentToken, quantityIn, price},
            salt
        );

        expect(contractId).to.equal(computeId);
    });
});
