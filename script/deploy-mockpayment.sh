#!/bin/sh

cp .env.plume-sepolia .env
source .env

forge script script/DeployMockTokens.s.sol:DeployMockTokens --rpc-url $RPC_URL -vvv --verifier blockscout --broadcast --verify --legacy
