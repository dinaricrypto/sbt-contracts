import "dotenv/config";
import { ethers } from "ethers";
import fs from 'fs';
import path from 'path';

const sellProcessorDataPath = path.resolve(__dirname, '../lib/sbt-deployments/src/v0.1.0/sell_processor.json');
const sellProcessorData = JSON.parse(fs.readFileSync(sellProcessorDataPath, 'utf8'));
const sellProcessorAbi = sellProcessorData.abi;

// token abi
const tokenAbi = [
  "function approve(address spender, uint256 value) external returns (bool)"
];

async function getContractVersion(contract: ethers.Contract): Promise<string> {
  let contractVersion = '1';
  try {
    contractVersion = await contract.version();
  } catch {
    // do nothing
  }
  return contractVersion;
}

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
  const assetTokenAddress = "0xed12e3394e78C2B0074aa4479b556043cC84503C";
  const paymentTokenAddress = "0x709CE4CB4b6c2A03a4f938bA8D198910E44c11ff";
  

  // setup provider and signer
  const provider = ethers.getDefaultProvider(RPC_URL);
  const signer = new ethers.Wallet(privateKey, provider);
  const chainId = Number((await provider.getNetwork()).chainId);
  const sellProcessorAddress = sellProcessorData.networkAddresses[chainId];

  // connect signer to payment token contract
  const assetToken = new ethers.Contract(
    assetTokenAddress,
    tokenAbi,
    signer,
  );

  // connect signer to sell processor contract
  const sellProcessor = new ethers.Contract(
    sellProcessorAddress,
    sellProcessorAbi,
    signer,
  );

  // ------------------ Configure Order ------------------

  // order amount
  const orderAmount = ethers.parseUnits("1", 18);

  // price estimate from quote in USDC/whole share
  const priceEstimate = ethers.parseUnits("150", 6);
  const proceedsEstimate = orderAmount * priceEstimate / ethers.parseUnits("1", 18);
  
  // get fees to add to order
  const fees = await sellProcessor.estimateTotalFeesForOrder(paymentTokenAddress, proceedsEstimate);
  console.log(`fees: ${ethers.formatUnits(fees, 6)}`);

  // ------------------ Approve Spend ------------------

  // approve buy processor to spend payment token
  const approveTx = await assetToken.approve(sellProcessorAddress, orderAmount);
  await approveTx.wait();
  console.log(`approve tx hash: ${approveTx.hash}`);

  // ------------------ Submit Order ------------------

  // submit request order transaction
  // see IOrderProcessor.Order struct for order parameters
  const tx = await sellProcessor.requestOrder([
    signer.address,
    assetTokenAddress,
    paymentTokenAddress,
    true,
    0,
    orderAmount,
    0,
    0,
    1,
  ])
  const receipt = await tx.wait();
  console.log(`tx hash: ${tx.hash}`);

  // get order id from event
  const events = receipt.logs.map((log: any) => sellProcessor.interface.parseLog(log));
  if (!events) throw new Error("no events");
  const orderEvent = events.find((event: any) => event && event.name === "OrderRequested");
  if (!orderEvent) throw new Error("no order event");
  const orderAccount = orderEvent.args[0];
  const orderAccountIndex = orderEvent.args[1];
  console.log(`Order Account: ${orderAccount}`);
  console.log(`Order Index for Account: ${orderAccountIndex}`);
  const orderId = await sellProcessor.getOrderId(orderAccount, orderAccountIndex);
  console.log(`Order ID: ${orderId}`);

  // use order id to get order status
  const remaining = await sellProcessor.getRemainingOrder(orderId);
  console.log(`Order Remaining: ${remaining}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
