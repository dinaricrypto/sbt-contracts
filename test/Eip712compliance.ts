import { expect } from "chai";
import { ethers } from "hardhat";

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
      1_000_000,
      5_000,
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
    const price = ethers.utils.parseEther("5");

    const types = {
      Order: [
        { name: "salt", type: "bytes32" },
        { name: "recipient", type: "address" },
        { name: "assetToken", type: "address" },
        { name: "paymentToken", type: "address" },
        { name: "sell", type: "bool" },
        { name: "orderType", type: "uint8" },
        { name: "assetTokenQuantity", type: "uint256" },
        { name: "paymentTokenQuantity", type: "uint256" },
        { name: "price", type: "uint256" },
        { name: "tif", type: "uint8" },
      ],
    };
    const OrderType = {
      MARKET: 1,
      // other order types
    };

    // Time in force
    const TIF = {
      GTC: 1,
    };

    const value = {
      salt,
      recipient,
      assetToken,
      paymentToken,
      sell: false,
      orderType: OrderType.MARKET,
      assetTokenQuantity: ethers.utils.parseEther("0"),
      paymentTokenQuantity: quantityIn,
      price,
      tif: TIF.GTC,
      fee: 0,
    };

    const encoder = ethers.utils._TypedDataEncoder.from(types);
    const computeId = encoder.hashStruct("Order", value);

    const contractId = await issuerImpl.getOrderId(
      {
        recipient,
        assetToken,
        paymentToken,
        sell: false,
        orderType: OrderType.MARKET,
        assetTokenQuantity: ethers.utils.parseEther("0"),
        paymentTokenQuantity: quantityIn,
        price,
        tif: TIF.GTC,
        fee: 0,
      },
      salt,
    );

    console.log(contractId);

    expect(contractId).to.equal(computeId);
  });
});
