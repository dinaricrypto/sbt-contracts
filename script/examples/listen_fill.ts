import "dotenv/config";
import { ethers } from "ethers";
import fs from 'fs';
import path from 'path';

const orderProcessorDataPath = path.resolve(__dirname, '../../lib/sbt-deployments/src/v0.4.0/order_processor.json');
const orderProcessorData = JSON.parse(fs.readFileSync(orderProcessorDataPath, 'utf8'));
const orderProcessorAbi = orderProcessorData.abi;

async function main() {

  // ------------------ Setup ------------------

  // get account to listen for
  const requester = process.env.USER_ACCOUNT;
  if (!requester) throw new Error("empty user address");

  // get websockets rpc url
  const RPC_URL = process.env.RPC_URL_WSS;
  if (!RPC_URL) throw new Error("empty rpc url");

  // setup provider and signer
  const provider = new ethers.providers.WebSocketProvider(RPC_URL);
  const chainId = Number((await provider.getNetwork()).chainId);
  console.log(`Chain ID: ${chainId}`);
  const orderProcessorAddress = orderProcessorData.networkAddresses[chainId];
  console.log(`Order Processor Address: ${orderProcessorAddress}`);

  // connect provider to order processor contract
  const orderProcessor = new ethers.Contract(
    orderProcessorAddress,
    orderProcessorAbi,
    provider,
  );

  // ------------------ Listen ------------------

  // fill event filter for a specific account
  const filter = orderProcessor.filters.OrderFill(null, requester);

  // listen for fill events
  orderProcessor.on(filter, (orderId, paymentToken, assetToken, requesterAccount, assetAmount, paymentAmount, feesTaken, sell) => {
    console.log(`Account ${requesterAccount} Order ${orderId} filled. Paid ${feesTaken} fees.`);
    if (sell) {
      console.log(`${assetToken}:${assetAmount} => ${paymentToken}:${paymentAmount}`);
     } else {
      console.log(`${paymentToken}:${paymentAmount} => ${assetToken}:${assetAmount}`);
     }
  });
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
