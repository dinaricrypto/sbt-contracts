import "dotenv/config";
import { ethers } from "ethers";
import fs from 'fs';
import path from 'path';

const buyProcessorDataPath = path.resolve(__dirname, '../lib/sbt-deployments/src/v0.1.0/buy_processor.json');
const buyProcessorData = JSON.parse(fs.readFileSync(buyProcessorDataPath, 'utf8'));
const buyProcessorAbi = buyProcessorData.abi;

// token abi
const tokenAbi = [
  "function approve(address spender, uint256 value) external returns (bool)"
];

async function main() {

  // ------------------ Setup ------------------

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
  const assetToken = "0xed12e3394e78C2B0074aa4479b556043cC84503C";
  const paymentTokenAddress = "0x709CE4CB4b6c2A03a4f938bA8D198910E44c11ff";

  // setup provider and signer
  const provider = ethers.getDefaultProvider(RPC_URL);
  const signer = new ethers.Wallet(privateKey, provider);
  const chainId = Number((await provider.getNetwork()).chainId);
  const buyProcessorAddress = buyProcessorData.networkAddresses[chainId];

  // connect signer to payment token contract
  const paymentToken = new ethers.Contract(
    paymentTokenAddress,
    tokenAbi,
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
  const orderAmount = BigInt(1000_000_000);

  // get fees to add to order
  const fees = await buyProcessor.estimateTotalFeesForOrder(paymentTokenAddress, orderAmount);
  const totalSpendAmount = orderAmount + fees;
  console.log(`fees: ${ethers.formatUnits(fees, 6)}`);

  // ------------------ Approve Spend ------------------

  // approve buy processor to spend payment token
  const approveTx = await paymentToken.approve(buyProcessorAddress, totalSpendAmount);
  await approveTx.wait();
  console.log(approveTx.hash);

  // ------------------ Submit Order ------------------

  // submit request order transaction
  // see IOrderProcessor.Order struct for order parameters
  const tx = await buyProcessor.requestOrder([
    signer.address,
    assetToken,
    paymentTokenAddress,
    false,
    0,
    0,
    orderAmount, // fees will be added to this amount
    0,
    1,
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
