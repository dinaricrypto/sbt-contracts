import "dotenv/config";
import { ethers } from "ethers";

async function main() {

  // ------------------ Setup ------------------

  // nonces abi
  const noncesAbi = [
    "function nonces(address owner) external view returns (uint256)",
  ];

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
  const RPC_URL = "https://eth-sepolia.g.alchemy.com/v2/POjQtmDHMgWYVnO3w9V3J6w4veLd3zrr";
  const buyProcessorAbi = getBuyProcessorAbi();
  const buyProcessorAddress = "0x1754422ef9910572cCde378a9C07d717eC8D48A0";
  const assetToken = "0xBCf1c387ced4655DdFB19Ea9599B19d4077f202D";
  const paymentTokenAddress = "0x45bA256ED2F8225f1F18D76ba676C1373Ba7003F";

  // setup provider and signer
  const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
  const signer = new ethers.Wallet(privateKey, provider);

  // connect signer to payment token contract
  const paymentToken = new ethers.Contract(
    paymentTokenAddress,
    noncesAbi,
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
  const orderAmount = ethers.utils.parseEther("10");

  // get fees to add to order
  // const fees = await buyProcessor.estimateTotalFeesForOrder(paymentToken.address, orderAmount);
  const { flatFee, _percentageFeeRate } = await buyProcessor.getFeeRatesForOrder(paymentToken.address);
  const fees = flatFee.add(orderAmount.mul(_percentageFeeRate).div(10000));
  const totalSpendAmount = orderAmount.add(fees);

  // ------------------ Configure Permit ------------------

  // permit nonce for user
  const nonce = await paymentToken.nonces(signer.address);
  // 5 minute deadline from current blocktime
  const deadline = (await provider.getBlock(await provider.getBlockNumber())).timestamp + 60 * 5;

  // unique signature domain for payment token
  const permitDomain = {
    name: 'USD Coin',
    version: '1',
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

  // submit permit + request order multicall transaction
  const tx = await buyProcessor.multicall([
    buyProcessor.interface.encodeFunctionData("selfPermit", [
      paymentToken.address,
      permitMessage.owner,
      permitMessage.value,
      permitMessage.deadline,
      permitSignature.v,
      permitSignature.r,
      permitSignature.s
    ]),
    // see IOrderProcessor.Order struct for order parameters
    buyProcessor.interface.encodeFunctionData("requestOrder", [[
      signer.address,
      assetToken,
      paymentToken.address,
      false,
      0,
      0,
      orderAmount, // fees will be added to this amount
      0,
      1,
    ]]),
  ]);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });



function getBuyProcessorAbi() {
  return `[
      {
        "inputs": [
          {
            "internalType": "address",
            "name": "_owner",
            "type": "address"
          },
          {
            "internalType": "address",
            "name": "_treasury",
            "type": "address"
          },
          {
            "internalType": "uint64",
            "name": "_perOrderFee",
            "type": "uint64"
          },
          {
            "internalType": "uint24",
            "name": "_percentageFeeRate",
            "type": "uint24"
          },
          {
            "internalType": "contract ITokenLockCheck",
            "name": "_tokenLockCheck",
            "type": "address"
          }
        ],
        "stateMutability": "nonpayable",
        "type": "constructor"
      },
      {
        "inputs": [],
        "name": "AmountTooLarge",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "Blacklist",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "DecimalsTooLarge",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "FeeTooLarge",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "InvalidOrderData",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "LimitPriceNotSet",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "NotRequester",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "OrderCancellationInitiated",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "OrderFillBelowLimitPrice",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "OrderNotFound",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "OrderTypeMismatch",
        "type": "error"
      },
      {
        "inputs": [
          {
            "internalType": "uint256",
            "name": "x",
            "type": "uint256"
          },
          {
            "internalType": "uint256",
            "name": "y",
            "type": "uint256"
          },
          {
            "internalType": "uint256",
            "name": "denominator",
            "type": "uint256"
          }
        ],
        "name": "PRBMath_MulDiv_Overflow",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "Paused",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "ZeroAddress",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "ZeroValue",
        "type": "error"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "address",
            "name": "recipient",
            "type": "address"
          },
          {
            "indexed": true,
            "internalType": "uint256",
            "name": "index",
            "type": "uint256"
          }
        ],
        "name": "CancelRequested",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [],
        "name": "DefaultAdminDelayChangeCanceled",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": false,
            "internalType": "uint48",
            "name": "newDelay",
            "type": "uint48"
          },
          {
            "indexed": false,
            "internalType": "uint48",
            "name": "effectSchedule",
            "type": "uint48"
          }
        ],
        "name": "DefaultAdminDelayChangeScheduled",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [],
        "name": "DefaultAdminTransferCanceled",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "address",
            "name": "newAdmin",
            "type": "address"
          },
          {
            "indexed": false,
            "internalType": "uint48",
            "name": "acceptSchedule",
            "type": "uint48"
          }
        ],
        "name": "DefaultAdminTransferScheduled",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": false,
            "internalType": "uint64",
            "name": "perOrderFee",
            "type": "uint64"
          },
          {
            "indexed": false,
            "internalType": "uint24",
            "name": "percentageFeeRate",
            "type": "uint24"
          }
        ],
        "name": "FeeSet",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "address",
            "name": "recipient",
            "type": "address"
          },
          {
            "indexed": true,
            "internalType": "uint256",
            "name": "index",
            "type": "uint256"
          },
          {
            "indexed": false,
            "internalType": "string",
            "name": "reason",
            "type": "string"
          }
        ],
        "name": "OrderCancelled",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "address",
            "name": "recipient",
            "type": "address"
          },
          {
            "indexed": true,
            "internalType": "uint256",
            "name": "index",
            "type": "uint256"
          },
          {
            "indexed": false,
            "internalType": "uint256",
            "name": "fillAmount",
            "type": "uint256"
          },
          {
            "indexed": false,
            "internalType": "uint256",
            "name": "receivedAmount",
            "type": "uint256"
          }
        ],
        "name": "OrderFill",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "address",
            "name": "recipient",
            "type": "address"
          },
          {
            "indexed": true,
            "internalType": "uint256",
            "name": "index",
            "type": "uint256"
          }
        ],
        "name": "OrderFulfilled",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "address",
            "name": "recipient",
            "type": "address"
          },
          {
            "indexed": true,
            "internalType": "uint256",
            "name": "index",
            "type": "uint256"
          },
          {
            "components": [
              {
                "internalType": "address",
                "name": "recipient",
                "type": "address"
              },
              {
                "internalType": "address",
                "name": "assetToken",
                "type": "address"
              },
              {
                "internalType": "address",
                "name": "paymentToken",
                "type": "address"
              },
              {
                "internalType": "bool",
                "name": "sell",
                "type": "bool"
              },
              {
                "internalType": "enum IOrderProcessor.OrderType",
                "name": "orderType",
                "type": "uint8"
              },
              {
                "internalType": "uint256",
                "name": "assetTokenQuantity",
                "type": "uint256"
              },
              {
                "internalType": "uint256",
                "name": "paymentTokenQuantity",
                "type": "uint256"
              },
              {
                "internalType": "uint256",
                "name": "price",
                "type": "uint256"
              },
              {
                "internalType": "enum IOrderProcessor.TIF",
                "name": "tif",
                "type": "uint8"
              }
            ],
            "indexed": false,
            "internalType": "struct IOrderProcessor.Order",
            "name": "order",
            "type": "tuple"
          }
        ],
        "name": "OrderRequested",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": false,
            "internalType": "bool",
            "name": "paused",
            "type": "bool"
          }
        ],
        "name": "OrdersPaused",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "bytes32",
            "name": "role",
            "type": "bytes32"
          },
          {
            "indexed": true,
            "internalType": "bytes32",
            "name": "previousAdminRole",
            "type": "bytes32"
          },
          {
            "indexed": true,
            "internalType": "bytes32",
            "name": "newAdminRole",
            "type": "bytes32"
          }
        ],
        "name": "RoleAdminChanged",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "bytes32",
            "name": "role",
            "type": "bytes32"
          },
          {
            "indexed": true,
            "internalType": "address",
            "name": "account",
            "type": "address"
          },
          {
            "indexed": true,
            "internalType": "address",
            "name": "sender",
            "type": "address"
          }
        ],
        "name": "RoleGranted",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "bytes32",
            "name": "role",
            "type": "bytes32"
          },
          {
            "indexed": true,
            "internalType": "address",
            "name": "account",
            "type": "address"
          },
          {
            "indexed": true,
            "internalType": "address",
            "name": "sender",
            "type": "address"
          }
        ],
        "name": "RoleRevoked",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "contract ITokenLockCheck",
            "name": "tokenLockCheck",
            "type": "address"
          }
        ],
        "name": "TokenLockCheckSet",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "address",
            "name": "treasury",
            "type": "address"
          }
        ],
        "name": "TreasurySet",
        "type": "event"
      },
      {
        "inputs": [],
        "name": "ASSETTOKEN_ROLE",
        "outputs": [
          {
            "internalType": "bytes32",
            "name": "",
            "type": "bytes32"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "DEFAULT_ADMIN_ROLE",
        "outputs": [
          {
            "internalType": "bytes32",
            "name": "",
            "type": "bytes32"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "FORWARDER_ROLE",
        "outputs": [
          {
            "internalType": "bytes32",
            "name": "",
            "type": "bytes32"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "OPERATOR_ROLE",
        "outputs": [
          {
            "internalType": "bytes32",
            "name": "",
            "type": "bytes32"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "PAYMENTTOKEN_ROLE",
        "outputs": [
          {
            "internalType": "bytes32",
            "name": "",
            "type": "bytes32"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "acceptDefaultAdminTransfer",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "address",
            "name": "newAdmin",
            "type": "address"
          }
        ],
        "name": "beginDefaultAdminTransfer",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "cancelDefaultAdminTransfer",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "components": [
              {
                "internalType": "address",
                "name": "recipient",
                "type": "address"
              },
              {
                "internalType": "address",
                "name": "assetToken",
                "type": "address"
              },
              {
                "internalType": "address",
                "name": "paymentToken",
                "type": "address"
              },
              {
                "internalType": "bool",
                "name": "sell",
                "type": "bool"
              },
              {
                "internalType": "enum IOrderProcessor.OrderType",
                "name": "orderType",
                "type": "uint8"
              },
              {
                "internalType": "uint256",
                "name": "assetTokenQuantity",
                "type": "uint256"
              },
              {
                "internalType": "uint256",
                "name": "paymentTokenQuantity",
                "type": "uint256"
              },
              {
                "internalType": "uint256",
                "name": "price",
                "type": "uint256"
              },
              {
                "internalType": "enum IOrderProcessor.TIF",
                "name": "tif",
                "type": "uint8"
              }
            ],
            "internalType": "struct IOrderProcessor.Order",
            "name": "order",
            "type": "tuple"
          },
          {
            "internalType": "uint256",
            "name": "index",
            "type": "uint256"
          },
          {
            "internalType": "string",
            "name": "reason",
            "type": "string"
          }
        ],
        "name": "cancelOrder",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "bytes32",
            "name": "id",
            "type": "bytes32"
          }
        ],
        "name": "cancelRequested",
        "outputs": [
          {
            "internalType": "bool",
            "name": "",
            "type": "bool"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "uint48",
            "name": "newDelay",
            "type": "uint48"
          }
        ],
        "name": "changeDefaultAdminDelay",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "defaultAdmin",
        "outputs": [
          {
            "internalType": "address",
            "name": "",
            "type": "address"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "defaultAdminDelay",
        "outputs": [
          {
            "internalType": "uint48",
            "name": "",
            "type": "uint48"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "defaultAdminDelayIncreaseWait",
        "outputs": [
          {
            "internalType": "uint48",
            "name": "",
            "type": "uint48"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "address",
            "name": "",
            "type": "address"
          },
          {
            "internalType": "address",
            "name": "",
            "type": "address"
          }
        ],
        "name": "escrowedBalanceOf",
        "outputs": [
          {
            "internalType": "uint256",
            "name": "",
            "type": "uint256"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "components": [
              {
                "internalType": "address",
                "name": "recipient",
                "type": "address"
              },
              {
                "internalType": "address",
                "name": "assetToken",
                "type": "address"
              },
              {
                "internalType": "address",
                "name": "paymentToken",
                "type": "address"
              },
              {
                "internalType": "bool",
                "name": "sell",
                "type": "bool"
              },
              {
                "internalType": "enum IOrderProcessor.OrderType",
                "name": "orderType",
                "type": "uint8"
              },
              {
                "internalType": "uint256",
                "name": "assetTokenQuantity",
                "type": "uint256"
              },
              {
                "internalType": "uint256",
                "name": "paymentTokenQuantity",
                "type": "uint256"
              },
              {
                "internalType": "uint256",
                "name": "price",
                "type": "uint256"
              },
              {
                "internalType": "enum IOrderProcessor.TIF",
                "name": "tif",
                "type": "uint8"
              }
            ],
            "internalType": "struct IOrderProcessor.Order",
            "name": "order",
            "type": "tuple"
          },
          {
            "internalType": "uint256",
            "name": "index",
            "type": "uint256"
          },
          {
            "internalType": "uint256",
            "name": "fillAmount",
            "type": "uint256"
          },
          {
            "internalType": "uint256",
            "name": "receivedAmount",
            "type": "uint256"
          }
        ],
        "name": "fillOrder",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "address",
            "name": "token",
            "type": "address"
          }
        ],
        "name": "getFeeRatesForOrder",
        "outputs": [
          {
            "internalType": "uint256",
            "name": "flatFee",
            "type": "uint256"
          },
          {
            "internalType": "uint24",
            "name": "_percentageFeeRate",
            "type": "uint24"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "address",
            "name": "token",
            "type": "address"
          },
          {
            "internalType": "uint256",
            "name": "orderValue",
            "type": "uint256"
          }
        ],
        "name": "getInputValueForOrderValue",
        "outputs": [
          {
            "internalType": "uint256",
            "name": "inputValue",
            "type": "uint256"
          },
          {
            "internalType": "uint256",
            "name": "flatFee",
            "type": "uint256"
          },
          {
            "internalType": "uint256",
            "name": "percentageFee",
            "type": "uint256"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "address",
            "name": "recipient",
            "type": "address"
          },
          {
            "internalType": "uint256",
            "name": "index",
            "type": "uint256"
          }
        ],
        "name": "getOrderId",
        "outputs": [
          {
            "internalType": "bytes32",
            "name": "",
            "type": "bytes32"
          }
        ],
        "stateMutability": "pure",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "bytes32",
            "name": "id",
            "type": "bytes32"
          }
        ],
        "name": "getRemainingOrder",
        "outputs": [
          {
            "internalType": "uint256",
            "name": "",
            "type": "uint256"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "bytes32",
            "name": "role",
            "type": "bytes32"
          }
        ],
        "name": "getRoleAdmin",
        "outputs": [
          {
            "internalType": "bytes32",
            "name": "",
            "type": "bytes32"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "bytes32",
            "name": "id",
            "type": "bytes32"
          }
        ],
        "name": "getTotalReceived",
        "outputs": [
          {
            "internalType": "uint256",
            "name": "",
            "type": "uint256"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "bytes32",
            "name": "role",
            "type": "bytes32"
          },
          {
            "internalType": "address",
            "name": "account",
            "type": "address"
          }
        ],
        "name": "grantRole",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "bytes32",
            "name": "role",
            "type": "bytes32"
          },
          {
            "internalType": "address",
            "name": "account",
            "type": "address"
          }
        ],
        "name": "hasRole",
        "outputs": [
          {
            "internalType": "bool",
            "name": "",
            "type": "bool"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "components": [
              {
                "internalType": "address",
                "name": "recipient",
                "type": "address"
              },
              {
                "internalType": "address",
                "name": "assetToken",
                "type": "address"
              },
              {
                "internalType": "address",
                "name": "paymentToken",
                "type": "address"
              },
              {
                "internalType": "bool",
                "name": "sell",
                "type": "bool"
              },
              {
                "internalType": "enum IOrderProcessor.OrderType",
                "name": "orderType",
                "type": "uint8"
              },
              {
                "internalType": "uint256",
                "name": "assetTokenQuantity",
                "type": "uint256"
              },
              {
                "internalType": "uint256",
                "name": "paymentTokenQuantity",
                "type": "uint256"
              },
              {
                "internalType": "uint256",
                "name": "price",
                "type": "uint256"
              },
              {
                "internalType": "enum IOrderProcessor.TIF",
                "name": "tif",
                "type": "uint8"
              }
            ],
            "internalType": "struct IOrderProcessor.Order",
            "name": "order",
            "type": "tuple"
          }
        ],
        "name": "hashOrder",
        "outputs": [
          {
            "internalType": "bytes32",
            "name": "",
            "type": "bytes32"
          }
        ],
        "stateMutability": "pure",
        "type": "function"
      },
      {
        "inputs": [
          {
            "components": [
              {
                "internalType": "address",
                "name": "recipient",
                "type": "address"
              },
              {
                "internalType": "address",
                "name": "assetToken",
                "type": "address"
              },
              {
                "internalType": "address",
                "name": "paymentToken",
                "type": "address"
              },
              {
                "internalType": "bool",
                "name": "sell",
                "type": "bool"
              },
              {
                "internalType": "enum IOrderProcessor.OrderType",
                "name": "orderType",
                "type": "uint8"
              },
              {
                "internalType": "uint256",
                "name": "assetTokenQuantity",
                "type": "uint256"
              },
              {
                "internalType": "uint256",
                "name": "paymentTokenQuantity",
                "type": "uint256"
              },
              {
                "internalType": "uint256",
                "name": "price",
                "type": "uint256"
              },
              {
                "internalType": "enum IOrderProcessor.TIF",
                "name": "tif",
                "type": "uint8"
              }
            ],
            "internalType": "struct IOrderProcessor.Order",
            "name": "order",
            "type": "tuple"
          }
        ],
        "name": "hashOrderCalldata",
        "outputs": [
          {
            "internalType": "bytes32",
            "name": "",
            "type": "bytes32"
          }
        ],
        "stateMutability": "pure",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "bytes32",
            "name": "id",
            "type": "bytes32"
          }
        ],
        "name": "isOrderActive",
        "outputs": [
          {
            "internalType": "bool",
            "name": "",
            "type": "bool"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "bytes[]",
            "name": "data",
            "type": "bytes[]"
          }
        ],
        "name": "multicall",
        "outputs": [
          {
            "internalType": "bytes[]",
            "name": "results",
            "type": "bytes[]"
          }
        ],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "numOpenOrders",
        "outputs": [
          {
            "internalType": "uint256",
            "name": "",
            "type": "uint256"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "ordersPaused",
        "outputs": [
          {
            "internalType": "bool",
            "name": "",
            "type": "bool"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "owner",
        "outputs": [
          {
            "internalType": "address",
            "name": "",
            "type": "address"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "pendingDefaultAdmin",
        "outputs": [
          {
            "internalType": "address",
            "name": "newAdmin",
            "type": "address"
          },
          {
            "internalType": "uint48",
            "name": "schedule",
            "type": "uint48"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "pendingDefaultAdminDelay",
        "outputs": [
          {
            "internalType": "uint48",
            "name": "newDelay",
            "type": "uint48"
          },
          {
            "internalType": "uint48",
            "name": "schedule",
            "type": "uint48"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "perOrderFee",
        "outputs": [
          {
            "internalType": "uint64",
            "name": "",
            "type": "uint64"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "percentageFeeRate",
        "outputs": [
          {
            "internalType": "uint24",
            "name": "",
            "type": "uint24"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "bytes32",
            "name": "role",
            "type": "bytes32"
          },
          {
            "internalType": "address",
            "name": "account",
            "type": "address"
          }
        ],
        "name": "renounceRole",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "address",
            "name": "recipient",
            "type": "address"
          },
          {
            "internalType": "uint256",
            "name": "index",
            "type": "uint256"
          }
        ],
        "name": "requestCancel",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "components": [
              {
                "internalType": "address",
                "name": "recipient",
                "type": "address"
              },
              {
                "internalType": "address",
                "name": "assetToken",
                "type": "address"
              },
              {
                "internalType": "address",
                "name": "paymentToken",
                "type": "address"
              },
              {
                "internalType": "bool",
                "name": "sell",
                "type": "bool"
              },
              {
                "internalType": "enum IOrderProcessor.OrderType",
                "name": "orderType",
                "type": "uint8"
              },
              {
                "internalType": "uint256",
                "name": "assetTokenQuantity",
                "type": "uint256"
              },
              {
                "internalType": "uint256",
                "name": "paymentTokenQuantity",
                "type": "uint256"
              },
              {
                "internalType": "uint256",
                "name": "price",
                "type": "uint256"
              },
              {
                "internalType": "enum IOrderProcessor.TIF",
                "name": "tif",
                "type": "uint8"
              }
            ],
            "internalType": "struct IOrderProcessor.Order",
            "name": "order",
            "type": "tuple"
          }
        ],
        "name": "requestOrder",
        "outputs": [
          {
            "internalType": "uint256",
            "name": "index",
            "type": "uint256"
          }
        ],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "bytes32",
            "name": "role",
            "type": "bytes32"
          },
          {
            "internalType": "address",
            "name": "account",
            "type": "address"
          }
        ],
        "name": "revokeRole",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "rollbackDefaultAdminDelay",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "address",
            "name": "token",
            "type": "address"
          },
          {
            "internalType": "address",
            "name": "owner",
            "type": "address"
          },
          {
            "internalType": "uint256",
            "name": "value",
            "type": "uint256"
          },
          {
            "internalType": "uint256",
            "name": "deadline",
            "type": "uint256"
          },
          {
            "internalType": "uint8",
            "name": "v",
            "type": "uint8"
          },
          {
            "internalType": "bytes32",
            "name": "r",
            "type": "bytes32"
          },
          {
            "internalType": "bytes32",
            "name": "s",
            "type": "bytes32"
          }
        ],
        "name": "selfPermit",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "uint64",
            "name": "_perOrderFee",
            "type": "uint64"
          },
          {
            "internalType": "uint24",
            "name": "_percentageFeeRate",
            "type": "uint24"
          }
        ],
        "name": "setFees",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "bool",
            "name": "pause",
            "type": "bool"
          }
        ],
        "name": "setOrdersPaused",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "contract ITokenLockCheck",
            "name": "_tokenLockCheck",
            "type": "address"
          }
        ],
        "name": "setTokenLockCheck",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "address",
            "name": "account",
            "type": "address"
          }
        ],
        "name": "setTreasury",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "bytes4",
            "name": "interfaceId",
            "type": "bytes4"
          }
        ],
        "name": "supportsInterface",
        "outputs": [
          {
            "internalType": "bool",
            "name": "",
            "type": "bool"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "tokenLockCheck",
        "outputs": [
          {
            "internalType": "contract ITokenLockCheck",
            "name": "",
            "type": "address"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "treasury",
        "outputs": [
          {
            "internalType": "address",
            "name": "",
            "type": "address"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      }
    ]`;
}
