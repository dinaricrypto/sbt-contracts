import "dotenv/config";
import { ethers } from "ethers";
import fs from 'fs';
import path from 'path';

async function main() {

  // ------------------ Setup ------------------

  // get account to listen for
  const requester = process.env.USER_ACCOUNT;
  if (!requester) throw new Error("empty user address");

  // get websockets rpc url
  const RPC_URL = process.env.RPC_URL_WSS;
  if (!RPC_URL) throw new Error("empty rpc url");

  // ------------------ Connect Abi------------------
  const orderProcessorDataPath = path.resolve(__dirname, '../../lib/sbt-deployments/src/v0.4.0/order_processor.json');
  let orderProcessorData: any;
  try {
    orderProcessorData = JSON.parse(fs.readFileSync(orderProcessorDataPath, 'utf8'));
  } catch (error) {
    throw new Error(`Error reading order processor data: ${error}`);
  }
  const orderProcessorAbi = orderProcessorData.abi;


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
  const filter: ethers.EventFilter = orderProcessor.filters.OrderFill(null);

  // Fetch all OrderFill events with the filter
  try {
    const allEvents = await orderProcessor.queryFilter(filter);
    console.log(`Fetched ${allEvents.length} events`);

    // Filter events to include only those with the specific requester address
    const filteredEvents = allEvents.filter(event => event.args && event.args.requester.toLowerCase() === requester.toLowerCase());
    console.log(`Filtered ${filteredEvents.length} events for requester ${requester}`);
    
    // Print only the filtered events
    filteredEvents.forEach(event => {
      if (event.args) {
        const { orderId, paymentToken, assetToken, requester, assetAmount, paymentAmount, feesTaken, sell } = event.args as unknown as {
          orderId: ethers.BigNumber,
          paymentToken: string,
          assetToken: string,
          requester: string,
          assetAmount: ethers.BigNumber,
          paymentAmount: ethers.BigNumber,
          feesTaken: ethers.BigNumber,
          sell: boolean
        };
        console.log('OrderFill event:', event);
        console.log(`Account ${requester} Order ${event.args[0]} filled. Paid ${feesTaken} fees.`);
        if (sell) {
          console.log(`${assetToken}:${assetAmount} => ${paymentToken}:${paymentAmount}`);
        } else {
          console.log(`${paymentToken}:${paymentAmount} => ${assetToken}:${assetAmount}`);
        }
      } else {
        console.log('Event args are undefined:', event);
      }
    });
  } catch (error) {
    console.error('Error fetching events:', error);
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });