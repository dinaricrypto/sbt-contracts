#!/bin/sh

cp .env.stage .env
source .env

forge verify-contract --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY --watch --constructor-args $(cast abi-encode "constructor(address,uint256)" "0x694AA1769357215DE4FAC081bf1f309aDC325306" "421502") 0x8e43115C298180ec40E90636eB9EEbFE3715C93A src/forwarder/Forwarder.sol:Forwarder
# no args
# forge verify-contract --chain-id 11155111 --watch 0x3B882Ca4deEeE2036DeCe54312bfe318bf08eFB7  src/orders/BuyUnlockedProcessor.sol:BuyUnlockedProcessor
