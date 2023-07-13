#!/bin/sh

source .env

forge verify-contract --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY --watch --constructor-args $(cast abi-encode "constructor(address,uint64,uint64)" "0x4181803232280371E02a875F51515BE57B215231" 1000000000000000000 5000000000000000) 0x98e600449dca79b56aacdabf7a473b6dfc9adff3 src/issuer/OrderFees.sol:OrderFees
