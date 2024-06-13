import "dotenv/config";
import { createWalletClient, http, Hex, getContract, formatUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import * as all from 'viem/chains';
import fs from 'fs';
import path from 'path';

const orderProcessorDataPath = path.resolve(__dirname, '../../lib/sbt-deployments/src/v0.4.0/order_processor.json');
const orderProcessorData = JSON.parse(fs.readFileSync(orderProcessorDataPath, 'utf8'));
const orderProcessorAbi = orderProcessorData.abi;

// token abi
const tokenAbi = [
    "function approve(address spender, uint256 value) external returns (bool)",
    "function decimals() external view returns (uint8)",
];

function getChain(chainId: number) {
    for (const chain of Object.values(all)) {
        if (chain.id === chainId) return chain;
    }

    throw new Error("Chain with id ${chainId} not found");
}

async function main() {

    // ------------------ Setup ------------------

    // setup values
    const privateKey = process.env.PRIVATE_KEY as Hex;
    if (!privateKey) throw new Error("empty key");
    const CHAINID_STR = process.env.CHAINID;
    if (!CHAINID_STR) throw new Error("empty chain id");
    const chainId = parseInt(CHAINID_STR);
    const RPC_URL = process.env.RPC_URL;
    if (!RPC_URL) throw new Error("empty rpc url");
    const assetTokenAddress = "0xed12e3394e78C2B0074aa4479b556043cC84503C"; // SPY
    const paymentTokenAddress = "0x709CE4CB4b6c2A03a4f938bA8D198910E44c11ff";

    // setup provider and signer
    const account = privateKeyToAccount(privateKey);
    const client = createWalletClient({ 
        account,
        chain: getChain(chainId), 
        transport: http(RPC_URL)
      })
    const orderProcessorAddress = orderProcessorData.networkAddresses[chainId];
    console.log(`Order Processor Address: ${orderProcessorAddress}`);

    // connect to payment token contract
    const paymentToken = getContract({
        address: paymentTokenAddress,
        abi: tokenAbi,
        client
    });

    // connect to asset token contract
    const assetToken = getContract({
        address: assetTokenAddress,
        abi: tokenAbi,
        client
    });

    // connect to buy processor contract
    const orderProcessor = getContract({
        address: orderProcessorAddress,
        abi: orderProcessorAbi,
        client
    });

    // ------------------ Configure Order ------------------

    // order amount (1000 USDC)
    const orderAmount = BigInt(1000_000_000);
    // buy order (Change to true for Sell Order)
    const sellOrder = false;
    // market order
    const orderType = Number(0);

    // check the order precision doesn't exceed max decimals
    // applicable to sell and limit orders only
    if (sellOrder || orderType === 1) {
        const maxDecimals = await orderProcessor.read.maxOrderDecimals([assetTokenAddress]) as bigint;
        const assetTokenDecimals = await assetToken.read.decimals() as bigint;
        const allowablePrecision = BigInt(10) ** (assetTokenDecimals - maxDecimals);
        if (orderAmount % allowablePrecision != BigInt(0)) {
            throw new Error(`Order amount precision exceeds max decimals of ${maxDecimals}`);
        }
    }

    // get fees from endpoint, fees will be added to buy order deposit or taken from sell order proceeds

    const fees = await orderProcessor.read.estimateTotalFeesForOrder([account.address, false, paymentTokenAddress, orderAmount]) as bigint;
    const totalSpendAmount = orderAmount + fees;
    console.log(`fees: ${formatUnits(fees, 6)}`);

    // ------------------ Approve Spend ------------------

    // approve buy processor to spend payment token
    const approveTxHash = await paymentToken.write.approve([orderProcessorAddress, totalSpendAmount]);
    console.log(`approve tx hash: ${approveTxHash}`);

    // ------------------ Submit Order ------------------

    // submit request order transaction
    // see IOrderProcessor.Order struct for order parameters
    const tx = await orderProcessor.write.requestOrder([
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
    ]);
    const receipt = await tx.wait();
    console.log(`tx hash: ${tx.hash}`);

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