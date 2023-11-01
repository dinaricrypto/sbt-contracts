import "dotenv/config";
import { ethers } from "ethers";
import fs from 'fs';
import path from 'path';

const sellProcessorDataPath = path.resolve(__dirname, '../lib/sbt-deployments/src/v0.1.0/sell_processor.json');
const sellProcessorData = JSON.parse(fs.readFileSync(sellProcessorDataPath, 'utf8'));
const sellProcessorAbi = sellProcessorData.abi;

// EIP-2612 abi
const eip2612Abi = [
  "function name() external view returns (string memory)",
  "function version() external view returns (string memory)",
  "function nonces(address owner) external view returns (uint256)",
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
    eip2612Abi,
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

  // ------------------ Configure Permit ------------------

  // permit nonce for user
  const nonce = await assetToken.nonces(signer.address);
  // 5 minute deadline from current blocktime
  const blockNumber = await provider.getBlockNumber();
  const blockTime = (await provider.getBlock(blockNumber))?.timestamp;
  if (!blockTime) throw new Error("no block time");
  const deadline = blockTime + 60 * 5;

  // unique signature domain for payment token
  const permitDomain = {
    name: await assetToken.name(),
    version: await getContractVersion(assetToken),
    chainId: (await provider.getNetwork()).chainId,
    verifyingContract: assetTokenAddress,
  };

  // permit message to sign
  const permitMessage = {
    owner: signer.address,
    spender: sellProcessorAddress,
    value: orderAmount,
    nonce: nonce,
    deadline: deadline
  };

  // sign permit to spend payment token
  const permitSignatureBytes = await signer.signTypedData(permitDomain, permitTypes, permitMessage);
  const permitSignature = ethers.Signature.from(permitSignatureBytes);

  // create selfPermit call data
  const selfPermitData = sellProcessor.interface.encodeFunctionData("selfPermit", [
    assetTokenAddress,
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
  const requestOrderData = sellProcessor.interface.encodeFunctionData("requestOrder", [[
    signer.address,
    assetTokenAddress,
    paymentTokenAddress,
    true,
    0,
    orderAmount,
    0,
    0,
    1,
  ]]);

  // submit permit + request order multicall transaction
  const tx = await sellProcessor.multicall([
    selfPermitData,
    requestOrderData,
  ]);
  const receipt = await tx.wait();
  console.log(tx.hash);

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
