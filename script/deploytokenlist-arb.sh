#!/bin/sh

source .env

forge script script/DeployTokenList.s.sol:DeployTokenListScript --rpc-url $RPC_ARBITRUM --etherscan-api-key $ARBISCAN_API_KEY --broadcast -vvvv
