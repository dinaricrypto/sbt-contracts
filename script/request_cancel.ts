import "dotenv/config";
import { ethers } from "ethers";
import fs from 'fs';
import path from 'path';

const buyProcessorDataPath = path.resolve(__dirname, 'sbt-deployments/src/v0.1.0/buy_processor.json');
const buyProcessorData = JSON.parse(fs.readFileSync(buyProcessorDataPath, 'utf8'));
const buyProcessorAbi = buyProcessorData.abi;
const buyProcessorAddress =  buyProcessorData.defaultAddress;

async function main() {

  // ------------------ Setup ------------------

  // setup values
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) throw new Error("empty key");
  const RPC_URL = process.env.TEST_RPC_URL;
  if (!RPC_URL) throw new Error("empty rpc url");

  // setup provider and signer
  const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
  const signer = new ethers.Wallet(privateKey, provider);

  // connect signer to buy processor contract
  const buyProcessor = new ethers.Contract(
    buyProcessorAddress,
    buyProcessorAbi,
    signer,
  );

  const index = 0;

  const tx = await buyProcessor.requestCancel(signer.address, index);
  console.log(`tx hash: ${tx.hash}`);
  await tx.wait();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });