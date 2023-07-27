import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

import { BuyOrderIssuer__factory } from "../typechain-types";

import type { BuyOrderIssuer } from "../typechain-types";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("EIP-712 Compliance Test", function () {
  let [deployer, user1, treasury]: SignerWithAddress[] = [];
  let issuerImpl: BuyOrderIssuer;

  before(async function () {
    [deployer, user1, treasury] = await ethers.getSigners();

    // Deploy OrderFees contract
    const orderFees = await ethers.deployContract("OrderFees", [
      deployer.address,
      ethers.utils.parseEther("1"),
      ethers.utils.parseEther("0.005"),
    ]);

    // Deploy BuyOrderIssuer contract
    const issuerFactory = new BuyOrderIssuer__factory(deployer);
    issuerImpl = issuerFactory.attach(
      (
        await ethers.deployContract("BuyOrderIssuer", [
          deployer.address,
          treasury.address,
          orderFees.address,
        ])
      ).address,
    );
  });

  it("Should correctly compute the EIP-712 typed data hash", async function () {
    const salt = ethers.utils.id(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
    );
    const recipient = user1.address;
    const assetToken = "0x0000000000000000000000000000000000000002";
    const paymentToken = "0x0000000000000000000000000000000000000003";
    const quantityIn = ethers.utils.parseEther("4");
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

    const encoder = ethers.utils._TypedDataEncoder.from(types);
    const computeId = encoder.hashStruct("OrderRequest", value);

    const contractId = await issuerImpl.getOrderIdFromOrderRequest(
      { recipient, assetToken, paymentToken, quantityIn, price },
      salt,
    );

    expect(contractId).to.equal(computeId);
  });
});
