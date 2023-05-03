#!/bin/sh

source .env

forge script script/DeployAll.s.sol:DeployAllScript --rpc-url $ARBITRUM_GOERLI_RPC_URL --broadcast --verify -vvvv
