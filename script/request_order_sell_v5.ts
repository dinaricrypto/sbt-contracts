import "dotenv/config";
import { ethers } from "ethers";
import fs from 'fs';
import path from 'path';

const sellProcessorDataPath = path.resolve(__dirname, '../lib/sbt-deployments/src/v0.1.0/buy_processor.json');
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
  const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
  const signer = new ethers.Wallet(privateKey, provider);
  const chainId = (await provider.getNetwork()).chainId;
  const buyProcessorAddress = buyProcessorData.networkAddresses[chainId];

  // connect signer to asset token contract
  const assetToken = new ethers.Contract(
    assetTokenAddress,
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
  const orderAmount = ethers.utils.parseUnits("1", "18");

  // price estimate USDC/whole share
  const priceEstimate = ethers.utils.parseUnits("150", "6");
  const proceedsEstimate = orderAmount.mul(priceEstimate).div(ethers.utils.parseUnits("1", "18"));

  // take fees from order
  // const fees = await buyProcessor.estimateTotalFeesForOrder(paymentToken.address, orderAmount);
  const { flatFee, _percentageFeeRate } = await buyProcessor.getFeeRatesForOrder(paymentTokenAddress);
  const fees = flatFee.add(proceedsEstimate.mul(_percentageFeeRate).div(10000));
  const totalReceivedEstimate = proceedsEstimate.sub(fees);
  console.log(`fees: ${ethers.utils.formatUnits(fees, "6")}`);
  console.log(`total received estimate: ${ethers.utils.formatUnits(totalReceivedEstimate, "6")}`);

  // ------------------ Configure Permit ------------------

  // permit nonce for user
  const nonce = await assetToken.nonces(signer.address);
  // 5 minute deadline from current blocktime
  const blockNumber = await provider.getBlockNumber();
  const deadline = (await provider.getBlock(blockNumber)).timestamp + 60 * 5;

  // unique signature domain for asset token
  const permitDomain = {
    name: await assetToken.name(),
    version: await getContractVersion(assetToken),
    chainId: provider.network.chainId,
    verifyingContract: assetTokenAddress,
  };

  // permit message to sign
  const permitMessage = {
    owner: signer.address,
    spender: buyProcessor.address,
    value: orderAmount,
    nonce: nonce,
    deadline: deadline
  };

  // sign permit to spend payment token
  const permitSignatureBytes = await signer._signTypedData(permitDomain, permitTypes, permitMessage);
  const permitSignature = ethers.utils.splitSignature(permitSignatureBytes);

  // create selfPermit call data
  const selfPermitData = buyProcessor.interface.encodeFunctionData("selfPermit", [
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
  const requestOrderData = buyProcessor.interface.encodeFunctionData("requestOrder", [[
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
