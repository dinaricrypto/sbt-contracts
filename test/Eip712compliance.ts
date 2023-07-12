import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

import type { BuyOrderIssuer } from "../typechain-types";
import type { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("EIP-712 Compliance Test", function () {
  let [deployer, user1, treasury]: SignerWithAddress[] = [];
  let issuerImpl: BuyOrderIssuer;

  before(async function () {
    [deployer, user1, treasury] = await ethers.getSigners();

    // Deploy OrderFees contract
    const orderFees = await ethers.deployContract("OrderFees", [
      deployer.address,
      ethers.parseEther("1"),
      ethers.parseEther("0.005"),
    ]);

    // Deploy BuyOrderIssuer contract
    const issuerFactory = await ethers.getContractFactory("BuyOrderIssuer");
    issuerImpl = await ethers.getContractAt(
      "BuyOrderIssuer",
      await (
        await upgrades.deployProxy(issuerFactory, [
          deployer.address,
          treasury.address,
          await orderFees.getAddress(),
        ])
      ).getAddress(),
    );
  });

  it("Should correctly compute the EIP-712 typed data hash", async function () {
    const salt = ethers.id(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
    );
    const recipient = user1.address;
    const assetToken = "0x0000000000000000000000000000000000000002";
    const paymentToken = "0x0000000000000000000000000000000000000003";
    const quantityIn = ethers.parseEther("4");
    const price = 5;

    const types = {
      OrderRequest: [
        { name: "salt", type: "bytes32" },
        { name: "recipient", type: "address" },
        { name: "assetToken", type: "address" },
        { name: "paymentToken", type: "address" },
        { name: "quantityIn", type: "uint256" },
      ],
    };

    const value = {
      salt,
      recipient,
      assetToken,
      paymentToken,
      quantityIn,
    };

    const encoder = ethers.TypedDataEncoder.from(types);
    const computeId = encoder.hashStruct("OrderRequest", value);

    const contractId = await issuerImpl.getOrderIdFromOrderRequest(
      { recipient, assetToken, paymentToken, quantityIn, price },
      salt,
    );

    expect(contractId).to.equal(computeId);
  });
});
