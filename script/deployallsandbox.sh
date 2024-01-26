#!/bin/sh

# cp .env.arb-sepolia .env
# source .env

# forge script script/DeployAllSandbox.s.sol:DeployAllSandbox --rpc-url $RPC_URL -vvv --broadcast --verify

cp .env.plume-sepolia .env
source .env

forge script script/DeployAllSandbox.s.sol:DeployAllSandbox --legacy --gas-limit 100000000 --rpc-url $RPC_URL --verifier blockscout -vvv --broadcast --verify
