import "dotenv/config";
import { ethers } from "ethers";
import fs from 'fs';
import path from 'path';

const orderProcessorDataPath = path.resolve(__dirname, '../../lib/sbt-deployments/src/v0.3.0/order_processor.json');
const orderProcessorData = JSON.parse(fs.readFileSync(orderProcessorDataPath, 'utf8'));
const orderProcessorAbi = orderProcessorData.abi;

async function main() {

  // ------------------ Setup ------------------

  // get account to listen for
  const requester = process.env.USER_ADDRESS;
  if (!requester) throw new Error("empty user address");

  // get websockets rpc url
  const RPC_URL = process.env.RPC_URL_WSS;
  if (!RPC_URL) throw new Error("empty rpc url");

  // setup provider and signer
  const provider = ethers.getDefaultProvider(RPC_URL);
  const chainId = Number((await provider.getNetwork()).chainId);
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
  await orderProcessor.on(filter, (event: ethers.ContractEventPayload) => {
    const [orderId, requesterAccount, fillAmount, receivedAmount, feesPaid] = event.args;
    console.log(`Account ${requesterAccount} Order ${orderId} filled for ${fillAmount}, received ${receivedAmount}, paid ${feesPaid}`);
  });

}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });