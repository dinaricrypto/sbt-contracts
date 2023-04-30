#!/bin/sh

source .env
export TOKEN_NAME="$1"
export TOKEN_SYMBOL="$2"

forge script script/DeployToken.s.sol:DeployTokenScript --rpc-url $ARBITRUM_GOERLI_RPC_URL --broadcast --verify -vvvv
