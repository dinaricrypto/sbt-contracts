import "dotenv/config";
import { ethers } from "ethers";
import fs from 'fs';
import path from 'path';

async function main() {

  // ------------------ Connect Abi------------------
  
  const orderProcessorDataPath = path.resolve(__dirname, '../../lib/sbt-deployments/src/v0.4.0/order_processor.json');
  let orderProcessorData: any;
  try {
    orderProcessorData = JSON.parse(fs.readFileSync(orderProcessorDataPath, 'utf8'));
  } catch (error) {
    throw new Error(`Error reading order processor data: ${error}`);
  }
  const orderProcessorAbi = orderProcessorData.abi;

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
  const filter: ethers.EventFilter = orderProcessor.filters.OrderFill();

  // Listen for new OrderFill events
  orderProcessor.on(filter, (orderId: ethers.BigNumber, paymentToken: string, assetToken: string, requesterAccount: string, assetAmount: ethers.BigNumber, paymentAmount: ethers.BigNumber, feesTaken: ethers.BigNumber, sell: boolean) => {
    console.log('New OrderFill event detected');
    if (requesterAccount.toLowerCase() === requester.toLowerCase()) {
      console.log(`Account ${requesterAccount} Order ${orderId.toString()} filled. Paid ${feesTaken.toString()} fees.`);
      if (sell) {
        console.log(`${assetToken}:${assetAmount.toString()} => ${paymentToken}:${paymentAmount.toString()}`);
      } else {
        console.log(`${paymentToken}:${paymentAmount.toString()} => ${assetToken}:${assetAmount.toString()}`);
      }
    }
  });

}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });