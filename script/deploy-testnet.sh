#!/bin/sh

source .env

forge script script/Deploy.s.sol:DeployScript --rpc-url $ARBITRUM_GOERLI_RPC_URL --broadcast --verify -vvvv
