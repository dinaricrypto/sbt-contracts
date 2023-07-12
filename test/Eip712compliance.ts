const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("EIP-712 Compliance Test", function() {
    let deployer, user1, treasury, orderFees;
    let BuyOrderIssuerFactory, OrderFeesFactory;
    let issuerImpl;

    before(async function() {
        [deployer, user1, treasury] = await ethers.getSigners();

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
        const salt = ethers.id(
            "0x0000000000000000000000000000000000000000000000000000000000000001"
        );
        const recipient = user1.address;
        const assetToken = "0x0000000000000000000000000000000000000000";
        const paymentToken = "0x0000000000000000000000000000000000000001";
        const quantityIn = ethers.parseEther("1");
        const price = 0;
    
        const types = {
            OrderRequest: [
                { name: "salt", type: "bytes32" },
                { name: "recipient", type: "address" },
                { name: "assetToken", type: "address" },
                { name: "paymentToken", type: "address" },
                { name: "quantityIn", type: "uint256" },
            ]
        };
    
        const value = {
            salt: salt,
            recipient: recipient,
            assetToken: assetToken,
            paymentToken: paymentToken,
            quantityIn: quantityIn,
        };
    
        const encoder = ethers.TypedDataEncoder.from(types);
        const computeId = encoder.hashStruct("OrderRequest", value);
    
        const contractId = await issuerImpl.getOrderIdFromOrderRequest(
            {recipient, assetToken, paymentToken, quantityIn, price},
            salt
        );
    
        expect(contractId).to.equal(computeId);
    });
});
