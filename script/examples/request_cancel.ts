import "dotenv/config";
import { ethers } from "ethers";
import fs from 'fs';
import path from 'path';

const orderProcessorDataPath = path.resolve(__dirname, '../../lib/sbt-deployments/src/v0.4.0/order_processor.json');
const orderProcessorData = JSON.parse(fs.readFileSync(orderProcessorDataPath, 'utf8'));
const orderProcessorAbi = orderProcessorData.abi;

async function main() {

  // ------------------ Setup ------------------

  // setup values
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) throw new Error("empty key");
  const RPC_URL = process.env.RPC_URL;
  if (!RPC_URL) throw new Error("empty rpc url");

  // setup provider and signer
  const provider = ethers.getDefaultProvider(RPC_URL);
  const signer = new ethers.Wallet(privateKey, provider);
  const chainId = Number((await provider.getNetwork()).chainId);
  const orderProcessorAddress = orderProcessorData.networkAddresses[chainId];
  console.log(`Order Processor Address: ${orderProcessorAddress}`);

  // connect signer to order processor contract
  const orderProcessor = new ethers.Contract(
    orderProcessorAddress,
    orderProcessorAbi,
    signer,
  );

  const orderId = 0;

  const tx = await orderProcessor.requestCancel(orderId);
  console.log(`tx hash: ${tx.hash}`);
  await tx.wait();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });