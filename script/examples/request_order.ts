import "dotenv/config";
import { ethers } from "ethers";
import fs from 'fs';
import path from 'path';

const orderProcessorDataPath = path.resolve(__dirname, '../../lib/sbt-deployments/src/v0.3.0/order_processor.json');
const orderProcessorData = JSON.parse(fs.readFileSync(orderProcessorDataPath, 'utf8'));
const orderProcessorAbi = orderProcessorData.abi;

// token abi
const tokenAbi = [
  "function name() external view returns (string memory)",
  "function decimals() external view returns (uint8)",
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
  const RPC_URL = process.env.RPC_URL;
  if (!RPC_URL) throw new Error("empty rpc url");
  const assetTokenAddress = "0xed12e3394e78C2B0074aa4479b556043cC84503C"; // SPY
  const paymentTokenAddress = "0x709CE4CB4b6c2A03a4f938bA8D198910E44c11ff";

  // setup provider and signer
  const provider = ethers.getDefaultProvider(RPC_URL);
  const signer = new ethers.Wallet(privateKey, provider);
  const chainId = Number((await provider.getNetwork()).chainId);
  const orderProcessorAddress = orderProcessorData.networkAddresses[chainId];
  console.log(`Order Processor Address: ${orderProcessorAddress}`);

  // connect signer to payment token contract
  const paymentToken = new ethers.Contract(
    paymentTokenAddress,
    tokenAbi,
    signer,
  );

  // connect signer to asset token contract
  const assetToken = new ethers.Contract(
    assetTokenAddress,
    tokenAbi,
    signer,
  );

  // connect signer to buy processor contract
  const orderProcessor = new ethers.Contract(
    orderProcessorAddress,
    orderProcessorAbi,
    signer,
  );

  // ------------------ Configure Order ------------------

  // buy order amount (1000 USDC)
  const orderAmount = BigInt(1000_000_000);
  // sell order amount (10 dShares)
  // const orderAmount = BigInt(10_000_000_000_000_000_000);
  // buy order (Change to true for Sell Order)
  const sellOrder = false;
  // market order
  const orderType = Number(0);

  // check the order precision doesn't exceed max decimals
  // applicable to sell and limit orders only
  if (sellOrder || orderType === 1) {
    const maxDecimals = await orderProcessor.maxOrderDecimals(assetTokenAddress);
    const assetTokenDecimals = await assetToken.decimals();
    const allowablePrecision = 10 ** (assetTokenDecimals - maxDecimals);
    if (Number(orderAmount) % allowablePrecision != 0) {
      throw new Error(`Order amount precision exceeds max decimals of ${maxDecimals}`);
    }
  }

  // get fees, fees will be added to buy order deposit or taken from sell order proceeds
  const fees = await orderProcessor.estimateTotalFeesForOrder(signer.address, false, paymentTokenAddress, orderAmount);
  const totalSpendAmount = orderAmount + fees;
  console.log(`fees: ${ethers.formatUnits(fees, 6)}`);

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
    name: await paymentToken.name(),
    version: await getContractVersion(paymentToken),
    chainId: (await provider.getNetwork()).chainId,
    verifyingContract: paymentTokenAddress,
  };

  // permit message to sign
  const permitMessage = {
    owner: signer.address,
    spender: orderProcessorAddress,
    value: totalSpendAmount,
    nonce: nonce,
    deadline: deadline
  };

  // sign permit to spend payment token
  const permitSignatureBytes = await signer.signTypedData(permitDomain, permitTypes, permitMessage);
  const permitSignature = ethers.Signature.from(permitSignatureBytes);

  // create selfPermit call data
  const selfPermitData = orderProcessor.interface.encodeFunctionData("selfPermit", [
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
  const requestOrderData = orderProcessor.interface.encodeFunctionData("requestOrder", [[
    signer.address,
    assetTokenAddress,
    paymentTokenAddress,
    sellOrder,
    orderType,
    0, // Asset amount to sell. Ignored for buys. Fees will be taken from proceeds for sells.
    orderAmount, // Payment amount to spend. Ignored for sells. Fees will be added to this amount for buys.
    0, // Unused limit price
    1, // GTC
    ethers.ZeroAddress, // split recipient
    0, // split amount
  ]]);

  // submit permit + request order multicall transaction
  const tx = await orderProcessor.multicall([
    selfPermitData,
    requestOrderData,
  ]);
  const receipt = await tx.wait();
  console.log(tx.hash);

  // get order id from event
  const events = receipt.logs.map((log: any) => orderProcessor.interface.parseLog(log));
  if (!events) throw new Error("no events");
  const orderEvent = events.find((event: any) => event && event.name === "OrderRequested");
  if (!orderEvent) throw new Error("no order event");
  const orderId = orderEvent.args[0];
  const orderAccount = orderEvent.args[1];
  console.log(`Order ID: ${orderId}`);
  console.log(`Order Account: ${orderAccount}`);

  // use order id to get order status (ACTIVE, FULFILLED, CANCELLED)
  const orderStatus = await orderProcessor.getOrderStatus(orderId);
  console.log(`Order Status: ${orderStatus}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
