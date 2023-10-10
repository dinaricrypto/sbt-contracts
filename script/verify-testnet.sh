#!/bin/sh

source .env

forge verify-contract --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY --watch --constructor-args $(cast abi-encode "constructor(address)" "0x702347E2B1be68444C1451922275b66AABDaC528") 0x080786a5673CA79Ff953897B1d6B8A95F52a0A98 src/dividend/DividendDistribution.sol:DividendDistribution
