#!/bin/sh

# cp .env.arb-sepolia .env
# source .env

# forge script script/DeployAllSandbox.s.sol:DeployAllSandbox --rpc-url $RPC_URL -vvv --broadcast --verify

cp .env.plume-sepolia .env
source .env

forge script script/DeployAllSandbox.s.sol:DeployAllSandbox --rpc-url $RPC_URL -vvv --broadcast --verify
