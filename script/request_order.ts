import "dotenv/config";
import { ethers } from "ethers";
import fs from 'fs';
import path from 'path';

const buyProcessorDataPath = path.resolve(__dirname, 'sbt-deployments/src/v0.1.0/buy_processor.json');
const buyProcessorData = JSON.parse(fs.readFileSync(buyProcessorDataPath, 'utf8'));
const buyProcessorAbi = buyProcessorData.abi;

async function main() {

  // ------------------ Setup ------------------

  // nonces abi
  const noncesAbi = [
    "function nonces(address owner) external view returns (uint256)",
  ];

  // permit EIP712 signature data type
  const permitTypes = {
    Permit: [
      {
        name: "owner",
        type: "address"
      },
      {
        name: "spender",
        type: "address"
      },
      {
        name: "value",
        type: "uint256"
      },
      {
        name: "nonce",
        type: "uint256"
      },
      {
        name: "deadline",
        type: "uint256"
      }
    ],
  };

  // setup values
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) throw new Error("empty key");
  const RPC_URL = process.env.TEST_RPC_URL;
  if (!RPC_URL) throw new Error("empty rpc url");
  const assetToken = "0xBCf1c387ced4655DdFB19Ea9599B19d4077f202D";
  const paymentTokenAddress = "0x45bA256ED2F8225f1F18D76ba676C1373Ba7003F";
  

  // setup provider and signer
  const provider = ethers.getDefaultProvider(RPC_URL);
  const signer = new ethers.Wallet(privateKey, provider);
  const chainId = Number((await provider.getNetwork()).chainId);
  const buyProcessorAddress = buyProcessorData.networkAddresses[chainId];

  // connect signer to payment token contract
  const paymentToken = new ethers.Contract(
    paymentTokenAddress,
    noncesAbi,
    signer,
  );

  // connect signer to buy processor contract
  const buyProcessor = new ethers.Contract(
    buyProcessorAddress,
    buyProcessorAbi,
    signer,
  );

  // ------------------ Configure Order ------------------

  // order amount
  const orderAmount = BigInt(10_000_000);

  // get fees to add to order
  // const fees = await buyProcessor.estimateTotalFeesForOrder(paymentToken.address, orderAmount);
  const { flatFee, _percentageFeeRate } = await buyProcessor.getFeeRatesForOrder(paymentTokenAddress);
  const fees = flatFee + (orderAmount * _percentageFeeRate) / BigInt(10000);
  const totalSpendAmount = orderAmount + fees;

  // ------------------ Configure Permit ------------------

  // permit nonce for user
  const nonce = await paymentToken.nonces(signer.address);
  // 5 minute deadline from current blocktime
  const blockNumber = await provider.getBlockNumber();
  const blockTime = (await provider.getBlock(blockNumber))?.timestamp;
  if (!blockTime) throw new Error("no block time");
  const deadline = blockTime + 60 * 5;

  // unique signature domain for payment token
  const permitDomain = {
    name: 'USD Coin',
    version: '1',
    chainId: (await provider.getNetwork()).chainId,
    verifyingContract: paymentTokenAddress,
  };

  // permit message to sign
  const permitMessage = {
    owner: signer.address,
    spender: buyProcessorAddress,
    value: totalSpendAmount,
    nonce: nonce,
    deadline: deadline
  };

  // sign permit to spend payment token
  const permitSignatureBytes = await signer.signTypedData(permitDomain, permitTypes, permitMessage);
  const permitSignature = ethers.Signature.from(permitSignatureBytes);

  // create selfPermit call data
  const selfPermitData = buyProcessor.interface.encodeFunctionData("selfPermit", [
    paymentTokenAddress,
    permitMessage.owner,
    permitMessage.value,
    permitMessage.deadline,
    permitSignature.v,
    permitSignature.r,
    permitSignature.s
  ]);

  // ------------------ Submit Order ------------------

  // create requestOrder call data
  // see IOrderProcessor.Order struct for order parameters
  const requestOrderData = buyProcessor.interface.encodeFunctionData("requestOrder", [[
    signer.address,
    assetToken,
    paymentTokenAddress,
    false,
    0,
    0,
    orderAmount, // fees will be added to this amount
    0,
    1,
  ]]);

  // submit permit + request order multicall transaction
  const tx = await buyProcessor.multicall([
    selfPermitData,
    requestOrderData,
  ]);
  const receipt = await tx.wait();
  console.log(tx.hash);

  // get order id from event
  const events = receipt.logs.map((log: any) => buyProcessor.interface.parseLog(log));
  if (!events) throw new Error("no events");
  const orderEvent = events.find((event: any) => event && event.name === "OrderRequested");
  if (!orderEvent) throw new Error("no order event");
  const orderAccount = orderEvent.args[0];
  const orderAccountIndex = orderEvent.args[1];
  console.log(`Order Account: ${orderAccount}`);
  console.log(`Order Index for Account: ${orderAccountIndex}`);
  const orderId = await buyProcessor.getOrderId(orderAccount, orderAccountIndex);
  console.log(`Order ID: ${orderId}`);

  // use order id to get order status
  const remaining = await buyProcessor.getRemainingOrder(orderId);
  console.log(`Order Remaining: ${remaining}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
