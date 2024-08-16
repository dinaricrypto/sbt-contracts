import "dotenv/config";
import { ethers } from "ethers";
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

async function main() {

    // ------------------ Setup ------------------

    // setup values
    const privateKey = process.env.PRIVATE_KEY;
    if (!privateKey) throw new Error("empty key");
    const RPC_URL = process.env.RPC_URL;
    if (!RPC_URL) throw new Error("empty rpc url");
    const assetTokenAddress = process.env.ASSETTOKEN;
    if (!assetTokenAddress) throw new Error("empty asset token address");
    const paymentTokenAddress = process.env.PAYMENTTOKEN;
    if (!paymentTokenAddress) throw new Error("empty payment token address");

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

    // order amount (1000 USDC)
    const orderAmount = BigInt(1000_000_000);
    // buy order (Change to true for Sell Order)
    const sellOrder = false;
    // market order
    const orderType = Number(0);

    // check the order precision doesn't exceed max decimals
    // applicable to sell orders only
    if (sellOrder) {
        const allowedDecimalReduction = await orderProcessor.orderDecimalReduction(assetTokenAddress);
        const allowablePrecisionReduction = 10 ** allowedDecimalReduction;
        if (Number(orderAmount) % allowablePrecisionReduction != 0) {
          const assetTokenDecimals = await assetToken.decimals();
          const maxDecimals = assetTokenDecimals - allowedDecimalReduction;
          throw new Error(`Order amount precision exceeds max decimals of ${maxDecimals}`);
        }
    }

    // get fees, fees will be added to buy order deposit or taken from sell order proceeds
    // TODO: get fees quote for sell order
    const fees = await orderProcessor.totalStandardFee(false, paymentTokenAddress, orderAmount);
    const totalSpendAmount = orderAmount + fees;
    console.log(`fees: ${ethers.utils.formatUnits(fees, 6)}`);

    // ------------------ Approve Spend ------------------

    // approve buy processor to spend payment token
    const approveTx = await paymentToken.approve(orderProcessorAddress, totalSpendAmount);
    await approveTx.wait();
    console.log(`approve tx hash: ${approveTx.hash}`);

    // ------------------ Submit Order ------------------

    // submit request order transaction
    // see IOrderProcessor.Order struct for order parameters
    const tx = await orderProcessor.createOrderStandardFees([
        Date.now(),
        signer.address,
        assetTokenAddress,
        paymentTokenAddress,
        sellOrder,
        orderType,
        0, // Asset amount to sell. Ignored for buys. Fees will be taken from proceeds for sells.
        orderAmount, // Payment amount to spend. Ignored for sells. Fees will be added to this amount for buys.
        0, // Unused limit price
        1, // GTC
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