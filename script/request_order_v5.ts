import "dotenv/config";
import { ethers } from "ethers";
import fs from 'fs';
import path from 'path';

const buyProcessorDataPath = path.resolve(__dirname, '../lib/sbt-deployments/src/v0.1.0/buy_processor.json');
const buyProcessorData = JSON.parse(fs.readFileSync(buyProcessorDataPath, 'utf8'));
const buyProcessorAbi = buyProcessorData.abi;

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
  const assetToken = "0xed12e3394e78C2B0074aa4479b556043cC84503C";
  const paymentTokenAddress = "0x709CE4CB4b6c2A03a4f938bA8D198910E44c11ff";

  // setup provider and signer
  const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
  const signer = new ethers.Wallet(privateKey, provider);
  const chainId = (await provider.getNetwork()).chainId;
  const buyProcessorAddress = buyProcessorData.networkAddresses[chainId];

  // connect signer to payment token contract
  const paymentToken = new ethers.Contract(
    paymentTokenAddress,
    eip2612Abi,
    signer,
  );

  // connect signer to buy processor contract
  const buyProcessor = new ethers.Contract(
    buyProcessorAddress,
    buyProcessorAbi,
    signer,
  );

  // ------------------ Configure Order ------------------

  // order amount
  const orderAmount = ethers.utils.parseUnits("1000", "6");

  // get fees to add to order
  const fees = await buyProcessor.estimateTotalFeesForOrder(paymentTokenAddress, orderAmount);
  const totalSpendAmount = orderAmount.add(fees);
  console.log(`fees: ${ethers.utils.formatUnits(fees, "6")}`);

  // ------------------ Configure Permit ------------------

  // permit nonce for user
  const nonce = await paymentToken.nonces(signer.address);
  // 5 minute deadline from current blocktime
  const blockNumber = await provider.getBlockNumber();
  const deadline = (await provider.getBlock(blockNumber)).timestamp + 60 * 5;

  // unique signature domain for payment token
  const permitDomain = {
    name: await paymentToken.name(),
    version: await getContractVersion(paymentToken),
    chainId: provider.network.chainId,
    verifyingContract: paymentTokenAddress,
  };

  // permit message to sign
  const permitMessage = {
    owner: signer.address,
    spender: buyProcessor.address,
    value: totalSpendAmount,
    nonce: nonce,
    deadline: deadline
  };

  // sign permit to spend payment token
  const permitSignatureBytes = await signer._signTypedData(permitDomain, permitTypes, permitMessage);
  const permitSignature = ethers.utils.splitSignature(permitSignatureBytes);

  // create selfPermit call data
  const selfPermitData = buyProcessor.interface.encodeFunctionData("selfPermit", [
    paymentToken.address,
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
  const requestOrderData = buyProcessor.interface.encodeFunctionData("requestOrder", [[
    signer.address,
    assetToken,
    paymentToken.address,
    false,
    0,
    0,
    orderAmount, // fees will be added to this amount
    0,
    1,
  ]]);

  // submit permit + request order multicall transaction
  const tx = await buyProcessor.multicall([
    selfPermitData,
    requestOrderData,
  ]);
  console.log(`tx hash: ${tx.hash}`);
  await tx.wait();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
