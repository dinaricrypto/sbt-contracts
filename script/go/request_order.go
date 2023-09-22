package main

import (
	"context"
	"crypto/ecdsa"
	"encoding/hex"
	"fmt"
	"log"
	"math/big"
	"os"
	"strings"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/math"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum/signer/core/apitypes"
	"github.com/joho/godotenv"
)

const (
	BuyProcessorAddress = "0x1754422ef9910572cCde378a9C07d717eC8D48A0"
	AssetToken          = "0xBCf1c387ced4655DdFB19Ea9599B19d4077f202D"
	PaymentTokenAddress = "0x45bA256ED2F8225f1F18D76ba676C1373Ba7003F"
)

// The structure to represent FeeRates, Message, OrderStruct.

type FeeRates struct {
	FlatFee           *big.Int
	PercentageFeeRate *big.Int
}

type Message struct {
	Owner    string
	Nonce    *big.Int
	Deadline *big.Int
}

type OrderStruct struct {
	Recipient            common.Address
	AssetToken           common.Address
	PaymentToken         common.Address
	Sell                 bool
	OrderType            uint8
	AssetTokenQuantity   *big.Int
	PaymentTokenQuantity *big.Int
	Price                *big.Int
	Tif                  uint8
}

// EIP712Hash calculates the EIP-712 compliant hash of the provided domain and message data.
//
// Parameters:
// - message: The PermitMessage containing the actual data we want to sign and hash.
//   - Owner: Address of the entity granting permission.
//   - Nonce: A unique value to prevent replay attacks.
//   - Deadline: The timestamp after which the message is considered expired.
//
// Returns:
// - []byte: The EIP-712 compliant hash of the provided data.
// - error: An error object indicating any issues encountered during hashing.
func EIP712Hash(message Message, chainId int64) ([]byte, error) {

	typesStandard := apitypes.Types{
		"EIP712Domain": {
			{
				Name: "name",
				Type: "string",
			},
			{
				Name: "version",
				Type: "string",
			},
			{
				Name: "chainId",
				Type: "uint256",
			},
			{
				Name: "verifyingContract",
				Type: "address",
			},
		},
		"Permit": {
			{
				Name: "owner",
				Type: "address",
			},
			{
				Name: "spender",
				Type: "address",
			},
			{
				Name: "value",
				Type: "uint256",
			},
			{
				Name: "nonce",
				Type: "uint256",
			},
			{
				Name: "deadline",
				Type: "uint256",
			},
		},
	}

	// Create the domain struct based on EIP712 requirements
	domainStruct := apitypes.TypedDataDomain{
		Name:              "USD Coin",
		Version:           "1",
		ChainId:           math.NewHexOrDecimal256(chainId),
		VerifyingContract: PaymentTokenAddress,
	}

	// Create the message struct for hashing
	permitStruct := map[string]interface{}{
		"owner":    message.Owner,
		"spender":  BuyProcessorAddress,
		"value":    0,
		"nonce":    message.Nonce,
		"deadline": message.Deadline,
	}

	// Define the DataTypes using previously defined types and the constructed structs
	DataTypes := apitypes.TypedData{
		Types:       typesStandard, // This should be defined elsewhere (or passed as an argument if dynamic)
		PrimaryType: "Permit",
		Domain:      domainStruct,
		Message:     permitStruct,
	}

	// Hash the domain struct
	domainHash, err := DataTypes.HashStruct("EIP712Domain", domainStruct.Map())
	if err != nil {
		return nil, err
	}

	// Hash the message struct
	messageHash, err := DataTypes.HashStruct("Permit", permitStruct)
	if err != nil {
		return nil, err
	}

	// Combine and hash the domain and message hashes according to EIP-712 and return
	return crypto.Keccak256(append([]byte("\x19\x01"), append(domainHash, messageHash...)...)), nil
}

func main() {
	// Load environment variables from .env file
	err := godotenv.Load("../../.env")
	if err != nil {
		log.Fatal("Error loading .env file")
	}

	// Establish a connection to the Ethereum client using the RPC URL from environment variables
	rpcURL := os.Getenv("TEST_RPC_URL")
	client, err := ethclient.Dial(rpcURL)
	if err != nil {
		log.Fatalf("Failed to connect to the Ethereum client: %v", err)
	}
	fmt.Println("we have a connection")

	// Retrieve private key from environment variable and derive the public key & Ethereum address
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
	fmt.Println("Initializing request Order for user:", fromAddress)

	// Setup the ABI (Application Binary Interface) and the contract binding for the processor contract
	processorAddress := common.HexToAddress(BuyProcessorAddress)
	fmt.Println("buy processor address at:", processorAddress)
	buyProcessorAbi, err := abi.JSON(strings.NewReader(buyProcessorAbiString))
	if err != nil {
		log.Fatalf("Failed to parse contract ABI: %v", err)
	}
	processorContract := bind.NewBoundContract(processorAddress, buyProcessorAbi, client, client, client)

	// Call the 'getFeeRatesForOrder' method on the contract to get fee rates
	var result []interface{}
	feeRates := &FeeRates{}
	result = append(result, feeRates)
	paymentTokenAddr := common.HexToAddress(PaymentTokenAddress)
	err = processorContract.Call(&bind.CallOpts{}, &result, "getFeeRatesForOrder", paymentTokenAddr)
	if err != nil {
		log.Fatalf("Failed to call getFeeRatesForOrder function: %v", err)
	}
	fmt.Println("processor fees:", feeRates.FlatFee, feeRates.PercentageFeeRate)

	// Calculate the total amount to spend considering fee rates
	orderAmount := new(big.Int).Mul(big.NewInt(10), big.NewInt(1e6))
	fees := new(big.Int).Mul(orderAmount, feeRates.PercentageFeeRate)
	fees.Div(fees, big.NewInt(10000))
	fees.Add(fees, feeRates.FlatFee)
	totalSpendAmount := new(big.Int).Add(orderAmount, fees)
	fmt.Println("Total Spend Amount:", totalSpendAmount.String())

	// Get nonce & block information to set up the transaction
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

	// Fetch the current block number & its details to derive a deadline for the transaction
	blockNumber, err := client.BlockNumber(context.Background())
	if err != nil {
		log.Fatalf("Failed to get block number: %v", err)
	}
	block, err := client.BlockByNumber(context.Background(), big.NewInt(int64(blockNumber)))
	if err != nil {
		log.Fatalf("Failed to get block details: %v", err)
	}
	deadline := block.Time() + 300
	deadlineBigInt := new(big.Int).SetUint64(deadline)
	fmt.Println("Deadline:", deadline)

	// Get the current network ID for signing the transaction
	chainID, err := client.NetworkID(context.Background())
	if err != nil {
		log.Fatalf("Failed to get network ID: %v", err)
	}

	// Create a signer for the transaction using the private key
	auth, _ := bind.NewKeyedTransactorWithChainID(privateKey, chainID)

	// Creating EIP-712 hash

	typedHash, err := EIP712Hash(
		Message{
			Owner:    fromAddress.String(),
			Nonce:    nonce,
			Deadline: deadlineBigInt,
		},
		chainID.Int64(),
	)
	if err != nil {
		log.Fatalf("Failed to create EIP-712 hash: %v", err)
	}

	// Signing the hash and constructing R, S and V components of the signature

	signature, err := crypto.Sign(typedHash, privateKey)
	if err != nil {
		log.Fatalf("Failed to sign EIP-712 hash: %v", err)
	}
	if signature[64] < 27 {
		signature[64] += 27
	}

	fmt.Printf("EIP-712 Signature: 0x%x\n", hex.EncodeToString(signature))

	r := signature[:32]
	s := signature[32:64]
	v := signature[64]

	fmt.Printf("R: 0x%x\n", r)
	fmt.Printf("S: 0x%x\n", s)
	fmt.Printf("V: %d\n", v)

	// Constructing function data for selfPermit
	var rArray, sArray [32]byte
	copy(rArray[:], r)
	copy(sArray[:], s)

	selfPermitData, err := buyProcessorAbi.Pack(
		"selfPermit",
		paymentTokenAddr,
		fromAddress,
		totalSpendAmount,
		deadlineBigInt,
		v,
		rArray,
		sArray,
	)

	// Constructing function data for requestOrder
	order := OrderStruct{
		Recipient:            fromAddress,
		AssetToken:           common.HexToAddress(AssetToken),
		PaymentToken:         paymentTokenAddr,
		Sell:                 false,
		OrderType:            0,
		AssetTokenQuantity:   big.NewInt(0),
		PaymentTokenQuantity: orderAmount,
		Price:                big.NewInt(0),
		Tif:                  1,
	}

	requestOrderData, err := buyProcessorAbi.Pack(
		"requestOrder",
		order,
	)
	if err != nil {
		log.Fatalf("Failed to encode requestOrder function data: %v", err)
	}

	// Multicall - executing multiple transactions in one call
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

	// Submitting the transaction and waiting for it to be mined

	tx, err := processorContract.Transact(opts, "multicall", multicallArgs)
	if err != nil {
		log.Fatalf("Failed to submit multicall transaction: %v", err)
	}

	// Verifying transaction status and printing result
	receipt, err := bind.WaitMined(context.Background(), client, tx)
	if err != nil {
		log.Fatalf("Failed to get transaction receipt: %v", err)
	}

	if receipt.Status == 0 {
		log.Fatalf("Transaction failed with receipt: %v", receipt)
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