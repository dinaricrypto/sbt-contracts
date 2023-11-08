#!/bin/sh

source .env

forge script script/DeployAll.s.sol:DeployAllScript --rpc-url $RPC_URL --etherscan-api-key $ARBISCAN_API_KEY --broadcast --verify -vvvv
