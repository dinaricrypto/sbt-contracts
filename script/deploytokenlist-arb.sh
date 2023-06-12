#!/bin/sh

source .env

forge script script/DeployTokenList.s.sol:DeployTokenListScript --rpc-url $ARB_URL --etherscan-api-key $ARBISCAN_API_KEY --broadcast -vvvv
