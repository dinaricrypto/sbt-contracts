import "dotenv/config";
import { ethers } from "ethers";
import fs from 'fs';
import path from 'path';
import axios from 'axios';

const orderProcessorDataPath = path.resolve(__dirname, '../../lib/sbt-deployments/src/v0.4.0/order_processor.json');
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
  const assetTokenAddress = process.env.ASSETTOKEN;
  if (!assetTokenAddress) throw new Error("empty asset token address");
  const paymentTokenAddress = process.env.PAYMENTTOKEN;
  if (!paymentTokenAddress) throw new Error("empty payment token address");
  const dinariApiKey = process.env.DINARI_API_KEY;
  if (!dinariApiKey) throw new Error("empty dinari api key");

  // setup axios
  const dinariClient = axios.create({
    baseURL: "https://api-enterprise.sandbox.dinari.com",
    headers: {
      "Authorization": `Bearer ${dinariApiKey}`,
      "Content-Type": "application/json",
    },
  });

  // setup provider and signer
  const provider = ethers.getDefaultProvider(RPC_URL);
  const signer = new ethers.Wallet(privateKey, provider);
  console.log(`Signer Address: ${signer.address}`);
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

  // buy order amount (100 USDC)
  const orderAmount = BigInt(100_000_000);
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

  const orderParams = {
    requestTimestamp: Date.now(),
    recipient: signer.address,
    assetToken: assetTokenAddress,
    paymentToken: paymentTokenAddress,
    sell: sellOrder,
    orderType: orderType,
    assetTokenQuantity: 0, // Asset amount to sell. Ignored for buys. Fees will be taken from proceeds for sells.
    paymentTokenQuantity: Number(orderAmount), // Payment amount to spend. Ignored for sells. Fees will be added to this amount for buys.
    price: 0, // Unused limit price
    tif: 1, // GTC
  };

  // get fees, fees will be added to buy order deposit or taken from sell order proceeds
  // TODO: get fees quote for sell order
  const feeQuoteData = {
    chain_id: chainId,
    contract_address: orderProcessorAddress,
    order_data: orderParams
  };
  const feeQuoteResponse = await dinariClient.post("/api/v1/web3/orders/fee", feeQuoteData);
  const fees = BigInt(feeQuoteResponse.data.fee_quote.fee);
  const totalSpendAmount = orderAmount + fees;
  console.log(`fees: ${ethers.utils.formatUnits(fees, 6)}`);

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
  const permitSignatureBytes = await signer._signTypedData(permitDomain, permitTypes, permitMessage);
  const permitSignature = ethers.utils.splitSignature(permitSignatureBytes);

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

  // createOrder call data
  // see IOrderProcessor.Order struct for order parameters
  const requestOrderData = orderProcessor.interface.encodeFunctionData("createOrder", [[
    orderParams.requestTimestamp,
    orderParams.recipient,
    orderParams.assetToken,
    orderParams.paymentToken,
    orderParams.sell,
    orderParams.orderType,
    orderParams.assetTokenQuantity,
    orderParams.paymentTokenQuantity,
    orderParams.price,
    orderParams.tif,
  ], [
    feeQuoteResponse.data.fee_quote.orderId,
    feeQuoteResponse.data.fee_quote.requester,
    feeQuoteResponse.data.fee_quote.fee,
    feeQuoteResponse.data.fee_quote.timestamp,
    feeQuoteResponse.data.fee_quote.deadline,
  ], feeQuoteResponse.data.fee_quote_signature]);

  // submit permit + create order multicall transaction
  const tx = await orderProcessor.multicall([
    selfPermitData,
    requestOrderData,
  ]);
  const receipt = await tx.wait();
  console.log(`tx hash: ${tx.hash}`);

  // get order id from event
  const orderEvent = receipt.logs.filter((log: any) => log.topics[0] === orderProcessor.interface.getEventTopic("OrderCreated")).map((log: any) => orderProcessor.interface.parseLog(log))[0];
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
