#!/bin/sh

source .env

forge script script/DeployMockPaymentToken.s.sol:DeployMockPaymentTokenScript --rpc-url $ARBITRUM_GOERLI_RPC_URL --broadcast --verify -vvvv
