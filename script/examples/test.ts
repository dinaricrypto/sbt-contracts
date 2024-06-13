import { createPublicClient, http } from 'viem';
import {arbitrum} from 'viem/chains';


async function main() {

  const publicClient = createPublicClient({
    chain: arbitrum,
    transport: http()
  });
  console.log(`Public client transport: ${publicClient.transport.url}`);

  const chainId = await publicClient.getChainId();
  console.log(`Chain ID: ${chainId}`);

  // const blockNumber = await publicClient.getBlockNumber();
  // console.log(`Block number: ${blockNumber}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
