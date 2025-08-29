import "dotenv/config";
import { BigNumber, ethers } from "ethers";
import fs from 'fs';
import path from 'path';
import Dinari from '@dinari/api-sdk';
import { fileURLToPath } from 'url';
import axios from "axios";
const BACKEND_BASE_URL = "";
const bodyObject = {};
const executableOrders = [];
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const orderProcessorDataPath = path.resolve(__dirname, '../../lib/sbt-deployments/src/v0.4.0/order_processor.json');
const orderProcessorData = JSON.parse(fs.readFileSync(orderProcessorDataPath, 'utf8'));
const orderProcessorAbi = orderProcessorData.abi;

const tokenAbi = [
    "function name() external view returns (string memory)",
    "function decimals() external view returns (uint8)",
    "function version() external view returns (string memory)",
    "function nonces(address owner) external view returns (uint256)",
    "function balanceOf(address account) external view returns (uint256)",
    "function approve(address spender, uint256 amount) external returns (bool)",
    "function allowance(address owner, address spender) external view returns (uint256)",
];

function getTokenAddress(chainId, tokens) {
    const entry = tokens.find(token => token.split(":")[1] === String(chainId));
    return entry ? entry.split(":")[2] : null;
}



const cratesPath = path.resolve(__dirname, "crates.json");
const crates = JSON.parse(fs.readFileSync(cratesPath, "utf8"));
console.log(`Found ${crates.length} crates to process.`);

async function getContractVersion(contract: ethers.Contract): Promise<string> {
    let contractVersion = '1';
    try {
        contractVersion = await contract.version();
    } catch {
        // do nothing
    }
    return contractVersion;
}

const permitTypes = {
    Permit: [
        { name: "owner", type: "address" },
        { name: "spender", type: "address" },
        { name: "value", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "deadline", type: "uint256" }
    ],
};

async function main() {
    const privateKey = process.env.PRIVATE_KEY;
    if (!privateKey) throw new Error("empty key");
    const RPC_URL = process.env.RPC_URL;
    if (!RPC_URL) throw new Error("empty rpc url");
    const paymentTokenAddress = process.env.PAYMENTTOKEN;
    if (!paymentTokenAddress) throw new Error("empty payment token address");



    const dinariClient = new Dinari({
        apiKeyID: process.env.DINARI_API_KEY,
        apiSecretKey: process.env.DINARI_API_SECRET_KEY,
        environment: 'sandbox',
    });
    let orderStatus = await dinariClient.v2.accounts.orders.retrieve("62817225254367918022578272618669363084889071303396674724708330820388337561168")
    const provider = ethers.getDefaultProvider(RPC_URL);
    const signer = new ethers.Wallet(privateKey, provider);
    console.log(`Signer Address: ${signer.address}`);

    const chainId = Number((await provider.getNetwork()).chainId);
    const orderProcessorAddress = orderProcessorData.networkAddresses[chainId];
    console.log(`Order Processor Address: ${orderProcessorAddress}`);

    const orderProcessor = new ethers.Contract(orderProcessorAddress, orderProcessorAbi, signer);


    const userData = await axios.get(`${BACKEND_BASE_URL}/user/${signer.address}`);
    bodyObject.type = "sell";
    bodyObject.wallet = signer.address;
    bodyObject.crateId = "68767c8ea5efff9dcb31f6a5";
    bodyObject.chainId = chainId;
    let crateInvestmentData;
    if (userData.data.data.subscribedCrates && userData.data.data.subscribedCrates.length > 0) {
        for (const crate of userData.data.data.subscribedCrates) {
            if (bodyObject.crateId === crate.crateId) {
                console.log("Subscribed crate found:", crate);
                crateInvestmentData = crate.userInvestment;
            }
        }
    } else {
        console.log("No subscribed crates found for this user.");
        return;
    }

    if (!crateInvestmentData) {
        console.log("No investment data found for the specified crate.");
        return;
    }


    const multiCallBytes: string[] = [];
    let totalUsdGoingToWithdraw = 0;

    for (const stock of crateInvestmentData.stockHoldings) {
        const _stock = stock.stockId;
        console.log(stock, "_stock");
        console.log(`\n📦 Processing Stock: ${_stock.dinari_id}`);

        const assetTokenAddress = getTokenAddress(chainId, _stock.tokens);
        console.log(`Asset Token Address: ${assetTokenAddress}`);
        if (!assetTokenAddress) {
            console.log(`⚠️ Skipping Stock ${_stock.dinari_id} (No token for chainId ${chainId})`);
            return;
        }
        const assetToken = new ethers.Contract(assetTokenAddress, tokenAbi, signer);
        const orderAmount = ethers.utils.parseUnits(stock.sharesOwned.toString(), await assetToken.decimals());
        console.log(`Order Amount: ${orderAmount}tokens`);

        const userBalance = await assetToken.balanceOf(await signer.getAddress());
        console.log(`User Balance: ${userBalance.toString()} tokens`);

        if (userBalance.lt(orderAmount)) {
            console.log(`⏩ Skipping Stock ${_stock.dinari_id} (Not enough balance)`);
            continue;
        }

        const sellOrder = true;
        const orderType = 0;
        let actualAmount = BigNumber.from(orderAmount);
        if (sellOrder) {
            const allowedDecimalReduction = await orderProcessor.orderDecimalReduction(assetTokenAddress);
            const allowablePrecisionReduction = 10 ** allowedDecimalReduction;
            const assetTokenDecimals = await assetToken.decimals();
            const maxDecimals = assetTokenDecimals - allowedDecimalReduction;
            console.log(`Max Decimals Allowed for Order Amount: ${maxDecimals}`);
            const scale = BigNumber.from(10).pow(assetTokenDecimals - allowedDecimalReduction);
            actualAmount = actualAmount.div(scale).mul(scale);

            console.log(`Adjusted Order Amount: ${actualAmount} tokens`);

            if (Number(actualAmount) % allowablePrecisionReduction != 0) {
                const assetTokenDecimals = await assetToken.decimals();
                console.log(`Asset Token Decimals: ${assetTokenDecimals}`);
                const maxDecimals = assetTokenDecimals - allowedDecimalReduction;
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
            assetTokenQuantity: actualAmount,
            paymentTokenQuantity: 0,
            price: 0,
            tif: 1,
        };

        const _order = {
            chain_id: `eip155:11155111`,
            order_side: 'SELL',
            order_tif: 'DAY',
            order_type: 'MARKET',
            stock_id: _stock.dinari_id,
            payment_token: orderParams.paymentToken,
            asset_token_quantity: actualAmount.toString()
        };

        const accountId = "019814c3-64d2-7611-a4b7-dcc7c068f6ea";
        const feeQuoteResponse = await dinariClient.v2.accounts.orders.stocks.eip155.getFeeQuote(accountId, _order);
        const fees = BigInt(feeQuoteResponse.order_fee_contract_object.fee_quote.fee);
        console.log(`💰 Fee: ${ethers.utils.formatUnits(fees, 6)} USDC`);

        const nonce = await assetToken.nonces(signer.address);
        const blockNumber = await provider.getBlockNumber();
        const blockTime = (await provider.getBlock(blockNumber))?.timestamp;
        if (!blockTime) throw new Error("no block time");
        const deadline = blockTime + 60 * 5;

        const balance = await assetToken.balanceOf(signer.address);
        console.log(`Asset Token Balance: ${ethers.utils.formatUnits(balance, await assetToken.decimals())}`);

        const permitDomain = {
            name: await assetToken.name(),
            version: await getContractVersion(assetToken),
            chainId: chainId,
            verifyingContract: assetTokenAddress,
        };

        const permitMessage = {
            owner: signer.address,
            spender: orderProcessorAddress,
            value: actualAmount,
            nonce: nonce,
            deadline: deadline
        };

        const permitSignatureBytes = await signer._signTypedData(permitDomain, permitTypes, permitMessage);
        const permitSignature = ethers.utils.splitSignature(permitSignatureBytes);
        
        const selfPermitData = orderProcessor.interface.encodeFunctionData("selfPermit", [
            assetTokenAddress,
            permitMessage.owner,
            permitMessage.value,
            permitMessage.deadline,
            permitSignature.v,
            permitSignature.r,
            permitSignature.s
        ]);

        multiCallBytes.push(selfPermitData);

        // const approveData = assetToken.interface.encodeFunctionData("approve", [
        //     orderProcessorAddress,
        //     actualAmount
        // ]);
        
        // multiCallBytes.push(approveData);

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
            feeQuoteResponse.order_fee_contract_object.fee_quote.orderId,
            feeQuoteResponse.order_fee_contract_object.fee_quote.requester,
            feeQuoteResponse.order_fee_contract_object.fee_quote.fee,
            feeQuoteResponse.order_fee_contract_object.fee_quote.timestamp,
            feeQuoteResponse.order_fee_contract_object.fee_quote.deadline,
        ], feeQuoteResponse.order_fee_contract_object.fee_quote_signature]);

        multiCallBytes.push(requestOrderData);

        executableOrders.push({
            stock: _stock._id,
            sharesOwned: ethers.utils.formatUnits(orderAmount, await assetToken.decimals()),
        });
        totalUsdGoingToWithdraw+= ethers.utils.formatUnits(orderAmount, await assetToken.decimals())* _stock.price;

    }

    if (multiCallBytes.length === 0) {
        console.log("⚠️ No orders to submit.");
        return;
    }

    console.log(`\n📤 Submitting multicall with ${multiCallBytes.length / 2} orders...`);
    const tx = await orderProcessor.multicall(multiCallBytes);
    const receipt = await tx.wait();
    console.log(`✅ tx hash: ${tx.hash}`);

    bodyObject.transactionHash =tx.hash;
    bodyObject.stockHoldings = executableOrders;
    bodyObject.totalAmountInvested = totalUsdGoingToWithdraw;


    const orderEvents = receipt.logs
        .filter((log: any) => log.topics[0] === orderProcessor.interface.getEventTopic("OrderCreated"))
        .map((log: any) => orderProcessor.interface.parseLog(log));

    const orderIds = [];
    if (orderEvents.length === 0) throw new Error("No OrderCreated events found");

    for (let i = 0; i < executableOrders.length; i++) {
        const orderEvent = orderEvents[i];
        const orderId = orderEvent.args[0];
        orderIds.push(orderId.toString());
        const orderAccount = orderEvent.args[1];
        const orderStatusCode = await orderProcessor.getOrderStatus(orderId);
        let orderStatusLabel = "Unknown";
        if (orderStatusCode === 0) orderStatusLabel = "Pending";
        else if (orderStatusCode === 1) orderStatusLabel = "Completed";
        console.log(`Order ${i + 1}:`);
        console.log(`- Order ID: ${orderId}`);
        console.log(`- Order Account: ${orderAccount}`);
        console.log(`- Order Status: ${orderStatusLabel} (${orderStatusCode})`);
    }
    bodyObject.totalFeesDeducted = 0;
    bodyObject.orderIds = orderIds;

    console.log("Body Object:", bodyObject) ;
    let res = await axios.post(`${BACKEND_BASE_URL}/transactions`, bodyObject);
    console.log("Backend Response:", res.data);
    console.log("✅ Updated crates.json");
    console.log("\n🎉 All done!");

}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
