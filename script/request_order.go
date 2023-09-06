package main

import (
    "fmt"
    "os"
    "log"
	"math/big"
	"encoding/json"
	"crypto/ecdsa"
	"strings"
	"context"
    "github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/crypto"
)

const (
    BuyProcessorAddress = "0x1754422ef9910572cCde378a9C07d717eC8D48A0"
    AssetToken = "0xBCf1c387ced4655DdFB19Ea9599B19d4077f202D"
    PaymentTokenAddress = "0x45bA256ED2F8225f1F18D76ba676C1373Ba7003F"
)

type FeeRates struct {
	FlatFee           *big.Int
	PercentageFeeRate *big.Int
}

type EIP712Domain struct {
	Name              string `json:"name"`
	Version           string `json:"version"`
	ChainId           *big.Int   `json:"chainId"`
	VerifyingContract string `json:"verifyingContract"`
}

type PermitMessage struct {
	Owner   common.Address `json:"owner"`
	Spender common.Address `json:"spender"`
	Value   *big.Int       `json:"value"`
	Nonce   *big.Int       `json:"nonce"`
	Deadline uint64        `json:"deadline"`
}

type Signature struct {
	V uint8
	R [32]byte
	S [32]byte
}

type OrderStruct struct {
    Recipient           common.Address
    AssetToken          common.Address
    PaymentToken        common.Address
    Sell                bool
    OrderType           uint8
    AssetTokenQuantity  *big.Int
    PaymentTokenQuantity *big.Int
    Price               *big.Int
    Tif                 uint8
}



func constructEIP712DomainSeparator(name, version string, chainID *big.Int, verifyingContract common.Address) []byte {
    domain := map[string]interface{}{
        "name":              name,
        "version":           version,
        "chainId":           chainID,
        "verifyingContract": verifyingContract.Hex(),
    }

    domainData, err := json.Marshal(domain)
    if err != nil {
        log.Fatalf("Failed to marshal domain: %v", err)
    }

    return crypto.Keccak256([]byte(domainData))
}


func main() {
    rpcURL := os.Getenv("TEST_RPC_URL")
    client, err := ethclient.Dial(rpcURL)
    if err != nil {
        log.Fatalf("Failed to connect to the Ethereum client: %v", err)
    }
	fmt.Println("we have a connection")
	_ = client

	privateKey, err := crypto.HexToECDSA(os.Getenv("PRIVATE_KEY"))
	if err != nil {
        log.Fatal(err)
    }
	publicKey := privateKey.Public()
	publicKeyECDSA, ok := publicKey.(*ecdsa.PublicKey)
    if !ok {
        log.Fatal("error casting public key to ECDSA")
    }
	fromAddress := crypto.PubkeyToAddress(*publicKeyECDSA)
	fmt.Println("Initializing request Order for user:",fromAddress)

	auth := bind.NewKeyedTransactor(privateKey)
	_ = auth

	processorAddress := common.HexToAddress(BuyProcessorAddress)
	fmt.Println("buy processor address at:",processorAddress)

	buyProcessorAbi, err := abi.JSON(strings.NewReader(buyProcessorAbiString))
	if err != nil {
		log.Fatalf("Failed to parse contract ABI: %v", err)
	}

	processorContract := bind.NewBoundContract(processorAddress, buyProcessorAbi, client, client, client)

	var result []interface{}

	// get Fees

	feeRates:= &FeeRates{}
	result = append(result, feeRates)
	paymentTokenAddr := common.HexToAddress(PaymentTokenAddress)
	err = processorContract.Call(&bind.CallOpts{}, &result, "getFeeRatesForOrder", paymentTokenAddr)
	if err != nil {
		log.Fatalf("Failed to call getFeeRatesForOrder function: %v", err)
	}

	fmt.Println("processor fees:", feeRates.FlatFee, feeRates.PercentageFeeRate)

	orderAmount := new(big.Int).Mul(big.NewInt(10), big.NewInt(1e18))

	fees := new(big.Int).Mul(orderAmount, feeRates.PercentageFeeRate)
	fees.Div(fees, big.NewInt(10000))
	fees.Add(fees, feeRates.FlatFee)

	totalSpendAmount := new(big.Int).Add(orderAmount, fees)

	fmt.Println("Total Spend Amount:", totalSpendAmount.String())

	// get Nonce
	noncesAbi, err := abi.JSON(strings.NewReader(NoncesAbiString))
	if err != nil {
		log.Fatalf("Failed to parse contract ABI: %v", err)
	}
	paymentTokenContract := bind.NewBoundContract(paymentTokenAddr, noncesAbi, client, client, client)

	nonce := new(big.Int)
	result = append(result, nonce)
	err = paymentTokenContract.Call(&bind.CallOpts{}, &result, "nonces", fromAddress)
	if err != nil {
		log.Fatalf("Failed to call nonces function: %v", err)
	}

	fmt.Println("Nonce:", nonce)

	blockNumber, err := client.BlockNumber(context.Background())
	if err != nil {
		log.Fatalf("Failed to get block number: %v", err)
	}

	block, err := client.BlockByNumber(context.Background(), big.NewInt(int64(blockNumber)))
	if err != nil {
		log.Fatalf("Failed to get block details: %v", err)
	}

	deadline := block.Time() + 300

	fmt.Println("Deadline:", deadline)

	// Permit Message

	chainID, err := client.NetworkID(context.Background())
	if err != nil {
		log.Fatalf("Failed to get network ID: %v", err)
	}

	domainSeparator := constructEIP712DomainSeparator("USD Coin", "1", chainID, common.HexToAddress(PaymentTokenAddress))

	permitMessage := PermitMessage{
        Owner:    fromAddress,
        Spender:  processorAddress,
        Value:    totalSpendAmount,
        Nonce:    nonce,
        Deadline: deadline,
    }

	typedData := map[string]interface{}{
		"types": map[string]interface{}{
			"EIP712Domain": []map[string]string{
				{"name": "name", "type": "string"},
				{"name": "version", "type": "string"},
				{"name": "chainId", "type": "uint256"},
				{"name": "verifyingContract", "type": "address"},
			},
			"PermitMessage": []map[string]string{
				{"name": "owner", "type": "address"},
				{"name": "spender", "type": "address"},
				{"name": "value", "type": "uint256"},
				{"name": "nonce", "type": "uint256"},
				{"name": "deadline", "type": "uint256"},
			},
		},
		"primaryType": "PermitMessage",
		"domain":      domainSeparator,
		"message":     permitMessage,
	}	

	// Convert the typed data to its raw form
    data, err := json.Marshal(typedData)
    if err != nil {
        log.Fatalf("Failed to marshal typed data: %v", err)
    }

    // Hash the data and sign it
    hashedData := crypto.Keccak256(data)
    signature, err := crypto.Sign(hashedData, privateKey)
    if err != nil {
        log.Fatalf("Failed to sign typed data: %v", err)
    }

    // Split the signature
    if len(signature) != 65 {
        log.Fatal("Signature length is wrong")
    }
    r := signature[:32]
    s := signature[32:64]
    v := signature[64]

    fmt.Println("R:", r)
    fmt.Println("S:", s)
    fmt.Println("V:", v)


	var rArray, sArray [32]byte
	copy(rArray[:], r)
	copy(sArray[:], s)

	deadlineBigInt := new(big.Int).SetUint64(permitMessage.Deadline)

	selfPermitData, err := buyProcessorAbi.Pack(
		"selfPermit", 
		paymentTokenAddr,
		permitMessage.Owner,
		permitMessage.Value,
		deadlineBigInt,
		v,
		rArray,
		sArray,
	)

	if err != nil {
		log.Fatalf("Failed to encode function data: %v", err)
	}

	// encode requestOrder
	order := OrderStruct{
		Recipient:           fromAddress,
		AssetToken:          common.HexToAddress(AssetToken),
		PaymentToken:        paymentTokenAddr,
		Sell:                false,
		OrderType:           0,  
		AssetTokenQuantity:  orderAmount,
		PaymentTokenQuantity: big.NewInt(0), 
		Price:               big.NewInt(0), 
		Tif:                 1,
	}

	requestOrderData, err := buyProcessorAbi.Pack(
		"requestOrder",
		order,
	)
	if err != nil {
		log.Fatalf("Failed to encode requestOrder function data: %v", err)
	}
	

	// multi call
	multicallArgs := [][]byte{
		selfPermitData,
		requestOrderData,
	}

	gasPrice, err := client.SuggestGasPrice(context.Background())
	if err != nil {
		log.Fatalf("Failed to suggest gas price: %v", err)
	}

	opts := &bind.TransactOpts{
		From:     fromAddress,
		Signer:   auth.Signer,
		GasLimit: 6721975,
		GasPrice: gasPrice,
		Value:    big.NewInt(0),
	}

	tx, err := processorContract.Transact(opts, "multicall", multicallArgs)
	if err != nil {
		log.Fatalf("Failed to submit multicall transaction: %v", err)
	}
	
	// tx receipt
	receipt, err := bind.WaitMined(context.Background(), client, tx)
	if err != nil {
		log.Fatalf("Failed to get transaction receipt: %v", err)
	}

	if receipt.Status == 0 {
		log.Fatal("Transaction failed!")
	} else {
		fmt.Printf("Transaction successful with hash: %s\n", tx.Hash().Hex())
	}	
}

const NoncesAbiString = `[
    {
      "inputs": [
        {
          "internalType": "address",
          "name": "account",
          "type": "address"
        },
        {
          "internalType": "uint256",
          "name": "currentNonce",
          "type": "uint256"
        }
      ],
      "name": "InvalidAccountNonce",
      "type": "error"
    },
    {
      "inputs": [
        {
          "internalType": "address",
          "name": "owner",
          "type": "address"
        }
      ],
      "name": "nonces",
      "outputs": [
        {
          "internalType": "uint256",
          "name": "",
          "type": "uint256"
        }
      ],
      "stateMutability": "view",
      "type": "function"
    }
]`


const buyProcessorAbiString = `[
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
  ]`