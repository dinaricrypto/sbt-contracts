#!/bin/sh

cp .env.plume-sepolia .env
source .env

forge script script/DeployMockPaymentTokens.s.sol:DeployMockPaymentTokens --rpc-url $RPC_URL -vvv --verifier blockscout --broadcast --verify --legacy
