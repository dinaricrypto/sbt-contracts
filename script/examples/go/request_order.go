package main

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"os"
	"strconv"
	"strings"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/math"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum/signer/core/apitypes"
	"github.com/joho/godotenv"
	hdwallet "github.com/miguelmota/go-ethereum-hdwallet"
)

const (
	AssetToken          = "0xed12e3394e78C2B0074aa4479b556043cC84503C"
	PaymentTokenAddress = "0x709CE4CB4b6c2A03a4f938bA8D198910E44c11ff"
)

type OrderFee struct {
	TotalFee *big.Int
}

type NameData struct {
	Name string
}

type NonceData struct {
	Nonce *big.Int
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
	SplitRecipient       common.Address
	SplitAmount          *big.Int
}

func main() {
	// ------------------ Setup ------------------

	permitTypes := apitypes.Types{
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

	// Load environment variables from .env file
	err := godotenv.Load("../../.env")
	if err != nil {
		log.Fatal("Error loading .env file")
	}

	// Establish a connection to the Ethereum client using the RPC URL from environment variables
	rpcURL := os.Getenv("RPC_URL")
	client, err := ethclient.Dial(rpcURL)
	if err != nil {
		log.Fatalf("Failed to connect to the Ethereum client: %v", err)
	}
	fmt.Println("we have a connection")

	// Retrieve mnemonic from environment variable and initialize an account
	mnemonic := os.Getenv("MNEMONIC")
	wallet, err := hdwallet.NewFromMnemonic(mnemonic)
	if err != nil {
		log.Fatal(err)
	}

	path := hdwallet.MustParseDerivationPath("m/44'/60'/0'/0/0")
	account, err := wallet.Derive(path, true)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println("User:", account.Address)

	// Retrieve private key for signing
	privateKey, err := wallet.PrivateKey(account)
	if err != nil {
		log.Fatal(err)
	}

	// Get the current network ID for signing the transaction
	chainID, err := client.ChainID(context.Background())
	if err != nil {
		log.Fatalf("Failed to get network ID: %v", err)
	}
	fmt.Println("chainID:", chainID)

	// Create a signer for the transaction using the private key
	signer, _ := bind.NewKeyedTransactorWithChainID(privateKey, chainID)

	// Setup the ABI (Application Binary Interface) and the contract binding for the processor contract
	data, err := os.ReadFile("../../../lib/sbt-deployments/src/v0.3.0/order_processor.json")
	if err != nil {
		log.Fatal(err)
	}

	var contractData map[string]interface{}
	err = json.Unmarshal(data, &contractData)
	if err != nil {
		log.Fatal(err)
	}

	// Use the default address from the loaded data if available, otherwise use the constant OrderProcessorAddress
	// Use networkAddresses map from JSON data
	networkAddresses, ok := contractData["networkAddresses"].(map[string]interface{})
	if !ok {
		log.Fatal("networkAddresses not found or not a valid map in contract data")
	}

	// Get the chain ID
	chainID, err = client.ChainID(context.Background())
	if err != nil {
		log.Fatal("Failed to get chain ID:", err)
	}

	// Convert chain ID to string
	chainIDStr := strconv.FormatUint(chainID.Uint64(), 10)

	// Get the contract address for the specific chain ID
	processorAddressStr, ok := networkAddresses[chainIDStr].(string)
	if !ok {
		// If the specific chain ID is not found, use the default address
		processorAddressStr, ok = networkAddresses["default"].(string)
		if !ok {
			log.Fatal("Contract address not found for the chain ID or default")
		}
	}

	processorAddress := common.HexToAddress(processorAddressStr)
	fmt.Println("order processor address at:", processorAddress)

	// Load ABI from file
	abiArray, ok := contractData["abi"].([]interface{})
	if !ok {
		log.Fatal("ABI not found or not a valid array in contract data")
	}

	// Convert the array to a JSON string
	abiBytes, err := json.Marshal(abiArray)
	if err != nil {
		log.Fatal("Failed to marshal ABI array to bytes:", err)
	}

	abiString := string(abiBytes)

	processorAbi, err := abi.JSON(strings.NewReader(abiString))
	if err != nil {
		log.Fatalf("Failed to parse contract ABI: %v", err)
	}

	// Create the processor contract instance
	processorContract := bind.NewBoundContract(processorAddress, processorAbi, client, client, client)

	// Get token ABI
	eip2612Abi, err := abi.JSON(strings.NewReader(eip2612AbiString))
	if err != nil {
		log.Fatalf("Failed to parse contract ABI: %v", err)
	}

	// ------------------ Configure Order ------------------

	// Set order amount (10 USDC)
	orderAmount := new(big.Int).Mul(big.NewInt(10), big.NewInt(1e6))
	fmt.Println("Order Amount:", orderAmount.String())
	// Set buy or sell (false = buy, true = sell)
	sellOrder := false
	// Set order type (0 = market, 1 = limit)
	orderType := uint8(0)

	// Check the order decimals does not exceed max decimals
	// Applicable to sell and limit orders only
	if sellOrder || orderType == 1 {
		// Call the 'maxOrderDecimals' method on the contract to get max order decimals
		var maxDecimalsTxResult []interface{}
		maxDecimals := new(big.Int)
		maxDecimalsTxResult = append(maxDecimalsTxResult, maxDecimals)
		err = processorContract.Call(&bind.CallOpts{}, &maxDecimalsTxResult, "maxOrderDecimals")
		if err != nil {
			log.Fatalf("Failed to call getOrderDecimals function: %v", err)
		}
		fmt.Println("Order Decimals:", maxDecimals)

		// Call 'decimals' method on the asset token contract to get token decimals
		var assetTokenDecimalsTxResult []interface{}
		assetTokenDecimals := new(big.Int)
		assetTokenDecimalsTxResult = append(assetTokenDecimalsTxResult, assetTokenDecimals)
		assetTokenContract := bind.NewBoundContract(common.HexToAddress(AssetToken), eip2612Abi, client, client, client)
		err = assetTokenContract.Call(&bind.CallOpts{}, &assetTokenDecimalsTxResult, "decimals")
		if err != nil {
			log.Fatalf("Failed to call decimals function: %v", err)
		}
		fmt.Println("Asset Token Decimals:", assetTokenDecimals)

		// Calculate the allowable decimals
		allowableDecimals := new(big.Int).Sub(assetTokenDecimals, maxDecimals)
		if new(big.Int).Mod(orderAmount, allowableDecimals) != big.NewInt(0) {
			log.Fatalf("Order amount exceeds max alloeable decimals: %v", allowableDecimals)
		}
	}

	// Call the 'estimateTotalFeesForOrder' method on the contract to get total fees
	var feeTxResult []interface{}
	fees := new(OrderFee)
	feeTxResult = append(feeTxResult, fees)
	paymentTokenAddr := common.HexToAddress(PaymentTokenAddress)
	err = processorContract.Call(&bind.CallOpts{}, &feeTxResult, "estimateTotalFeesForOrder", account.Address, false, paymentTokenAddr, orderAmount)
	if err != nil {
		log.Fatalf("Failed to call estimateTotalFeesForOrder function: %v", err)
	}
	fmt.Println("processor fees:", fees.TotalFee)

	// Calculate the total amount to spend considering fee rates
	totalSpendAmount := new(big.Int).Add(orderAmount, fees.TotalFee)
	fmt.Println("Total Spend Amount:", totalSpendAmount.String())

	// ------------------ Configure Permit ------------------

	// Call the 'name' method on the payment token contract to get token name
	paymentTokenContract := bind.NewBoundContract(paymentTokenAddr, eip2612Abi, client, client, client)
	var nameTxResult []interface{}
	name := new(NameData)
	nameTxResult = append(nameTxResult, name)
	err = paymentTokenContract.Call(&bind.CallOpts{}, &nameTxResult, "name")
	if err != nil {
		log.Fatalf("Failed to call name function: %v", err)
	}
	fmt.Println("Name:", name.Name)
	var nonceTxResult []interface{}
	nonce := new(NonceData)
	nonceTxResult = append(nonceTxResult, nonce)
	err = paymentTokenContract.Call(&bind.CallOpts{}, &nonceTxResult, "nonces", account.Address)
	if err != nil {
		log.Fatalf("Failed to call nonces function: %v", err)
	}
	fmt.Println("Nonce:", nonce.Nonce)

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

	// Create the domain struct based on EIP712 requirements
	domainStruct := apitypes.TypedDataDomain{
		Name:              name.Name,
		Version:           "1", // Version may be different in the wild
		ChainId:           math.NewHexOrDecimal256(chainID.Int64()),
		VerifyingContract: PaymentTokenAddress,
	}

	// Create the message struct for hashing
	permitDataStruct := map[string]interface{}{
		"owner":    account.Address.String(),
		"spender":  processorAddress.String(),
		"value":    totalSpendAmount,
		"nonce":    nonce.Nonce,
		"deadline": deadlineBigInt,
	}

	// Define the DataTypes using previously defined types and the constructed structs
	DataTypes := apitypes.TypedData{
		Types:       permitTypes, // This should be defined elsewhere (or passed as an argument if dynamic)
		PrimaryType: "Permit",
		Domain:      domainStruct,
		Message:     permitDataStruct,
	}

	// Hash the domain struct
	domainHash, err := DataTypes.HashStruct("EIP712Domain", domainStruct.Map())
	if err != nil {
		log.Fatalf("Failed to create EIP-712 domain hash: %v", err)
	}
	fmt.Println("Domain Separator: ", domainHash.String())

	// Hash the message struct
	permitTypeHash := DataTypes.TypeHash("Permit")
	fmt.Println("Permit Type Hash: ", permitTypeHash.String())
	messageHash, err := DataTypes.HashStruct("Permit", permitDataStruct)
	if err != nil {
		log.Fatalf("Failed to create EIP-712 hash: %v", err)
	}
	fmt.Println("Permit Message Hash: ", messageHash.String())

	// Combine and hash the domain and message hashes according to EIP-712
	typedHash := crypto.Keccak256(append([]byte("\x19\x01"), append(domainHash, messageHash...)...))

	// Sign the hash and construct R, S and V components of the signature
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

	selfPermitData, err := processorAbi.Pack(
		"selfPermit",
		paymentTokenAddr,
		account.Address,
		totalSpendAmount,
		deadlineBigInt,
		v,
		rArray,
		sArray,
	)
	if err != nil {
		log.Fatalf("Failed to encode selfPermit function data: %v", err)
	}

	// ------------------ Submit Order ------------------

	// Constructing function data for requestOrder
	order := OrderStruct{
		Recipient:            account.Address,
		AssetToken:           common.HexToAddress(AssetToken),
		PaymentToken:         paymentTokenAddr,
		Sell:                 sellOrder,
		OrderType:            orderType,
		AssetTokenQuantity:   big.NewInt(0),
		PaymentTokenQuantity: orderAmount,
		Price:                big.NewInt(0),
		Tif:                  1,
		SplitRecipient:       common.BigToAddress(big.NewInt(0)),
		SplitAmount:          big.NewInt(0),
	}

	requestOrderData, err := processorAbi.Pack(
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

	// Estimate gas limit for the transaction
	gasPrice, err := client.SuggestGasPrice(context.Background())
	if err != nil {
		log.Fatalf("Failed to suggest gas price: %v", err)
	}

	opts := &bind.TransactOpts{
		From:     account.Address,
		Signer:   signer.Signer,
		GasLimit: 6721975, // Could be replaced with EstimateGas
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
		log.Fatalf("Transaction failed with hash: %s\n", tx.Hash().Hex())
	} else {
		fmt.Printf("Transaction successful with hash: %s\n", tx.Hash().Hex())
	}
}

const eip2612AbiString = `[
	{"type":"function","name":"name","inputs":[],"outputs":[{"name":"","type":"string","internalType":"string"}],"stateMutability":"view"},
	{"type":"function","name":"decimals","inputs":[],"outputs":[{"name":"","type":"uint8","internalType":"uint8"}],"stateMutability":"view"},
    {"type":"function","name":"nonces","inputs":[{"name":"owner","type":"address","internalType":"address"}],"outputs":[{"name":"result","type":"uint256","internalType":"uint256"}],"stateMutability":"view"}
]`
